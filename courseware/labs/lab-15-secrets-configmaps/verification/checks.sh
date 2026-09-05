#!/usr/bin/env bash
# Lab 15 — Secrets, ConfigMaps and Safe Injection
#
# Asserts that the live ConfigMap/Secret content still matches the fixtures in
# data/, that both injection styles behaved as taught, and RECORDS honestly
# whether this cluster encrypts Secrets at rest (on stock kind it does not).
#
# Usage:  bash verification/checks.sh
# Env:    KUBECTL (default "kubectl"), NS (default "kcna-lab15")

set -uo pipefail

KUBECTL="${KUBECTL:-kubectl}"
NS="${NS:-kcna-lab15}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB="$(cd "${HERE}/.." && pwd)"
DATA="${LAB}/data"

PASSED=0
FAILED=0
pass() { printf 'PASS  %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

# Portable base64 decode: GNU/BusyBox use -d, older macOS uses -D.
b64d() {
  if printf 'aGk=' | base64 -d >/dev/null 2>&1; then
    base64 -d
  else
    base64 -D
  fi
}

echo "== Lab 15 verification: Secrets, ConfigMaps and safe injection =="

if "$KUBECTL" get namespace "$NS" >/dev/null 2>&1; then
  pass "namespace $NS exists"
else
  fail "namespace $NS exists"
  echo "-- $PASSED passed, $FAILED failed --"
  exit 1
fi

# ---------------------------------- ConfigMap still matches the data fixture --
live_json="$("$KUBECTL" get configmap booking-app-config -n "$NS" \
  -o jsonpath='{.data.app-settings\.json}' 2>/dev/null)"
file_json="$(cat "${DATA}/app-settings.json" 2>/dev/null)"
if [ -n "$live_json" ] && [ "$(printf '%s' "$live_json" | tr -d '\n ')" = "$(printf '%s' "$file_json" | tr -d '\n ')" ]; then
  pass "ConfigMap booking-app-config app-settings.json matches data/app-settings.json byte-for-byte"
else
  fail "ConfigMap booking-app-config app-settings.json does not match data/app-settings.json"
fi

flags_ok=1
flags_seen=0
while IFS='=' read -r fk fv; do
  case "$fk" in ''|\#*) continue ;; esac
  flags_seen=$((flags_seen + 1))
  live_v="$("$KUBECTL" get configmap booking-app-config -n "$NS" \
    -o jsonpath="{.data.${fk}}" 2>/dev/null)"
  [ "$live_v" = "$fv" ] || flags_ok=0
done < "${DATA}/feature-flags.env"
if [ "$flags_ok" -eq 1 ] && [ "$flags_seen" -eq 4 ]; then
  pass "ConfigMap booking-app-config has all ${flags_seen} keys from data/feature-flags.env with matching values"
else
  fail "ConfigMap booking-app-config feature flags mismatch (seen=${flags_seen} ok=${flags_ok})"
fi

imm="$("$KUBECTL" get configmap booking-app-config-v1 -n "$NS" \
  -o jsonpath='{.immutable}' 2>/dev/null)"
if [ "$imm" = "true" ]; then
  pass "ConfigMap booking-app-config-v1 is immutable"
else
  fail "ConfigMap booking-app-config-v1 is immutable (got '${imm}')"
fi

# ---------------------------- Secret matches the fixture, and decodes to it ---
sec_keys_ok=1
sec_vals_ok=1
sec_dummy_ok=1
sec_seen=0
while IFS='=' read -r sk sv; do
  case "$sk" in ''|\#*) continue ;; esac
  sec_seen=$((sec_seen + 1))
  enc="$("$KUBECTL" get secret booking-credentials -n "$NS" \
    -o jsonpath="{.data.${sk}}" 2>/dev/null)"
  if [ -z "$enc" ]; then
    sec_keys_ok=0
    continue
  fi
  dec="$(printf '%s' "$enc" | b64d 2>/dev/null)"
  [ "$dec" = "$sv" ] || sec_vals_ok=0
  case "$dec" in
    DUMMY-*) : ;;
    *) sec_dummy_ok=0 ;;
  esac
done < "${DATA}/dummy-credentials.env"

if [ "$sec_keys_ok" -eq 1 ] && [ "$sec_seen" -eq 3 ]; then
  pass "Secret booking-credentials has all ${sec_seen} keys from data/dummy-credentials.env"
else
  fail "Secret booking-credentials is missing keys from data/dummy-credentials.env (seen=${sec_seen})"
fi

if [ "$sec_vals_ok" -eq 1 ]; then
  pass "Secret booking-credentials values base64-decode to the data/dummy-credentials.env values"
else
  fail "Secret booking-credentials values do not base64-decode to the fixture values"
fi

if [ "$sec_dummy_ok" -eq 1 ]; then
  pass "Secret booking-credentials contains only obvious DUMMY placeholders"
else
  fail "Secret booking-credentials contains a value that is NOT a DUMMY- placeholder - remove it immediately"
fi

ex_data="$("$KUBECTL" get secret booking-api-example -n "$NS" \
  -o jsonpath='{.data.EXAMPLE_PASSWORD}' 2>/dev/null)"
ex_string="$("$KUBECTL" get secret booking-api-example -n "$NS" \
  -o jsonpath='{.stringData}' 2>/dev/null)"
if [ -n "$ex_data" ] && [ -z "$ex_string" ]; then
  pass "Secret booking-api-example stores stringData as base64 under .data and returns no stringData"
else
  fail "Secret booking-api-example: data='${ex_data}' stringData='${ex_string}'"
fi

# --------------------------------------------------- environment injection ---
env_dump="$("$KUBECTL" exec -n "$NS" env-consumer -- env 2>/dev/null)"

if printf '%s\n' "$env_dump" | grep -q '^GREETING=Meridian Freight booking API$'; then
  pass "env-consumer resolved GREETING from a configMapKeyRef"
else
  fail "env-consumer resolved GREETING from a configMapKeyRef"
fi

if printf '%s\n' "$env_dump" | grep -q '^DB_USERNAME=DUMMY-not-a-real-username$'; then
  pass "env-consumer resolved DB_USERNAME from a secretKeyRef"
else
  fail "env-consumer resolved DB_USERNAME from a secretKeyRef"
fi

cfg_count="$(printf '%s\n' "$env_dump" | grep -c '^CFG_FEATURE_')"
if [ "${cfg_count:-0}" -eq 4 ]; then
  pass "env-consumer bulk-imported the FEATURE_* keys with the CFG_ prefix"
else
  fail "env-consumer bulk-imported the FEATURE_* keys with the CFG_ prefix (found ${cfg_count})"
fi

if printf '%s\n' "$env_dump" | grep -q '^OPTIONAL_TUNING='; then
  fail "env-consumer omitted the optional key that does not exist - but OPTIONAL_TUNING is set"
else
  pass "env-consumer omitted the optional key that does not exist"
fi

# -------------------------------------------------------- volume injection ---
vfiles="$("$KUBECTL" exec -n "$NS" volume-consumer -- \
  ls /etc/booking/config 2>/dev/null | sort | tr '\n' ' ')"
if [ "$vfiles" = "app-settings.json greeting.txt " ]; then
  pass "volume-consumer projected only the 2 requested ConfigMap keys, with greeting.txt renamed"
else
  fail "volume-consumer /etc/booking/config contains '${vfiles}', expected 'app-settings.json greeting.txt '"
fi

perm="$("$KUBECTL" exec -n "$NS" volume-consumer -- \
  sh -c 'ls -lLn /etc/booking/credentials/BOOKING_DB_PASSWORD' 2>/dev/null)"
if printf '%s' "$perm" | grep -q '^-r--r-----' && printf '%s' "$perm" | grep -q ' 1000 '; then
  pass "volume-consumer secret file mode is 0440 with group 1000 (fsGroup)"
else
  fail "volume-consumer secret file permissions unexpected: '${perm}'"
fi

if "$KUBECTL" exec -n "$NS" volume-consumer -- \
    sh -c 'mount | grep -q "on /etc/booking/credentials type tmpfs"' 2>/dev/null; then
  pass "volume-consumer secret volume is tmpfs (never written to node disk)"
else
  fail "volume-consumer secret volume is tmpfs (never written to node disk)"
fi

sp="$("$KUBECTL" get pod volume-consumer -n "$NS" \
  -o jsonpath='{.spec.containers[0].volumeMounts[?(@.subPath=="app-settings.json")].mountPath}' 2>/dev/null)"
if [ "$sp" = "/etc/booking/pinned-settings.json" ]; then
  pass "volume-consumer subPath mount exists alongside the directory mount"
else
  fail "volume-consumer subPath mount exists alongside the directory mount (got '${sp}')"
fi

# ----------- honest environment record: is anything encrypted at rest here? ---
enc_flag="$("$KUBECTL" get pod -n kube-system -l component=kube-apiserver \
  -o jsonpath='{.items[0].spec.containers[0].command}' 2>/dev/null \
  | tr ',' '\n' | grep -c 'encryption-provider-config')"
if [ "${enc_flag:-0}" -eq 0 ]; then
  pass "RECORDED: this cluster has NO --encryption-provider-config (Secrets are plaintext in etcd)"
else
  pass "RECORDED: this cluster DOES set --encryption-provider-config (Secrets are encrypted at rest)"
fi

echo "-- $PASSED passed, $FAILED failed --"
[ "$FAILED" -eq 0 ]
