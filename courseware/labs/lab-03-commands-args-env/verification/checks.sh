#!/usr/bin/env bash
# Lab 03 — Commands, Arguments and Environment
# Verification script. Creates nothing; scoped to namespace kcna-lab03.
set -uo pipefail

NS="kcna-lab03"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${LAB_DIR}/data"
PASS=0
FAIL=0

ok()    { printf '  [PASS] %s\n' "$1"; PASS=$((PASS+1)); }
bad()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
skip()  { printf '  [SKIP] %s\n' "$1"; }
head1() { printf '\n== %s\n' "$1"; }

head1 "0. Cluster reachability"
if kubectl version -o json >/dev/null 2>&1; then
  ok "kubectl can reach the API server"
else
  bad "kubectl cannot reach the API server"
  echo; echo "Result: ${PASS} passed, ${FAIL} failed"; exit 1
fi

head1 "1. Namespace and ConfigMaps built from data/"
if kubectl get namespace "${NS}" >/dev/null 2>&1; then
  ok "namespace ${NS} exists"
else
  bad "namespace ${NS} is missing"
fi

RD_KEYS="$(kubectl -n "${NS}" get configmap route-defaults \
  -o go-template='{{range $k,$v := .data}}{{$k}} {{end}}' 2>/dev/null)"
EXPECTED_KEYS="$(grep -c '^[A-Z]' "${DATA_DIR}/route-defaults.env" 2>/dev/null || echo 0)"
FOUND_KEYS="$(printf '%s' "${RD_KEYS}" | wc -w | tr -d ' ')"
if [ "${FOUND_KEYS}" = "${EXPECTED_KEYS}" ] && [ "${EXPECTED_KEYS}" != "0" ]; then
  ok "ConfigMap route-defaults has ${FOUND_KEYS} keys, matching data/route-defaults.env"
else
  bad "ConfigMap route-defaults has ${FOUND_KEYS} keys, expected ${EXPECTED_KEYS} (use --from-env-file)"
fi

TR="$(kubectl -n "${NS}" get configmap tariff-rates \
  -o go-template='{{index .data "tariff-rates.json"}}' 2>/dev/null)"
if printf '%s' "${TR}" | grep -q 'meridianfreight/tariff-rates/v1'; then
  ok "ConfigMap tariff-rates carries data/tariff-rates.json"
else
  bad "ConfigMap tariff-rates missing or does not contain the shipped JSON"
fi

head1 "2. ENTRYPOINT / CMD override matrix"
A_PHASE="$(kubectl -n "${NS}" get pod em-a-image-defaults -o jsonpath='{.status.phase}' 2>/dev/null)"
if [ "${A_PHASE}" = "Running" ]; then
  ok "A (no command/args): nginx runs from the image ENTRYPOINT + CMD"
else
  bad "A (no command/args) phase is '${A_PHASE:-<absent>}' (expected Running)"
fi

B_LOG="$(kubectl -n "${NS}" logs em-b-args-only 2>/dev/null)"
if printf '%s' "${B_LOG}" | grep -q 'docker-entrypoint.sh'; then
  ok "B (args only): the image ENTRYPOINT still ran"
else
  bad "B (args only): no /docker-entrypoint.sh banner — ENTRYPOINT did not run"
fi
if printf '%s' "${B_LOG}" | grep -q 'nginx version:'; then
  ok "B (args only): image CMD was replaced by args ['nginx','-v']"
else
  bad "B (args only): expected an 'nginx version:' line"
fi

C_LOG="$(kubectl -n "${NS}" logs em-c-command-override 2>/dev/null)"
if printf '%s' "${C_LOG}" | grep -q 'image ENTRYPOINT was replaced by spec.command'; then
  ok "C (command set): spec.command ran instead of the image ENTRYPOINT"
else
  bad "C (command set): expected marker line not found in logs"
fi
if printf '%s' "${C_LOG}" | grep -q 'docker-entrypoint.sh'; then
  bad "C (command set): the ENTRYPOINT banner appeared — command did not override it"
else
  ok "C (command set): no ENTRYPOINT banner, so ENTRYPOINT and CMD were both discarded"
fi

head1 "3. booking-config Pod: env, envFrom and downward API"
PHASE="$(kubectl -n "${NS}" get pod booking-config -o jsonpath='{.status.phase}' 2>/dev/null)"
if [ "${PHASE}" = "Running" ]; then
  ok "Pod booking-config phase is Running"
else
  bad "Pod booking-config phase is '${PHASE:-<absent>}' (expected Running)"
fi

LOG="$(kubectl -n "${NS}" logs booking-config 2>/dev/null)"
for expect in \
  'DEPOT_REGION=sg-west' \
  'DEPOT_CODE=MF-SIN-02' \
  'MF_DEPOT_CODE=MF-SIN-02' \
  'BOOKING_ENDPOINT=http://booking.kcna-lab03.svc.cluster.local:8080' \
  'MEM_LIMIT_MI=64' \
  'tariff entries: 10' \
  'booking-config ready'
do
  if printf '%s' "${LOG}" | grep -qF "${expect}"; then
    ok "log contains '${expect}'"
  else
    bad "log is missing '${expect}'"
  fi
done

if printf '%s' "${LOG}" | grep -q 'NODE_NAME=..*'; then
  ok "downward API injected NODE_NAME"
else
  bad "NODE_NAME was empty — check the fieldRef"
fi

# The optional envFrom reference must NOT have blocked start-up.
OPT="$(kubectl -n "${NS}" get pod booking-config \
  -o jsonpath='{.spec.containers[0].envFrom[2].configMapRef.optional}' 2>/dev/null)"
if [ "${OPT}" = "true" ]; then
  ok "the missing ConfigMap route-overrides is referenced with optional: true"
else
  bad "third envFrom entry is not marked optional (got '${OPT:-<absent>}')"
fi

head1 "4. Failure injection: CrashLoopBackOff evidence"
if kubectl -n "${NS}" get pod booking-missing-env >/dev/null 2>&1; then
  REASON="$(kubectl -n "${NS}" get pod booking-missing-env \
    -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null)"
  EXITC="$(kubectl -n "${NS}" get pod booking-missing-env \
    -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}' 2>/dev/null)"
  RESTARTS="$(kubectl -n "${NS}" get pod booking-missing-env \
    -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)"
  if [ "${REASON}" = "CrashLoopBackOff" ]; then
    ok "booking-missing-env is in CrashLoopBackOff as designed"
  else
    bad "booking-missing-env waiting reason is '${REASON:-<none>}' (expected CrashLoopBackOff)"
  fi
  if [ "${EXITC}" = "1" ]; then
    ok "lastState.terminated.exitCode is 1 (the preflight refused to start)"
  else
    bad "lastState.terminated.exitCode is '${EXITC:-<absent>}' (expected 1)"
  fi
  if [ -n "${RESTARTS}" ] && [ "${RESTARTS}" -ge 1 ] 2>/dev/null; then
    ok "restartCount is ${RESTARTS} (>=1)"
  else
    bad "restartCount is '${RESTARTS:-<absent>}'"
  fi
  if kubectl -n "${NS}" logs booking-missing-env --previous 2>/dev/null \
       | grep -q 'FATAL: TARIFF_TABLE is not set'; then
    ok "kubectl logs --previous shows the FATAL preflight message"
  else
    bad "could not read the FATAL message from the previous container instance"
  fi
else
  skip "booking-missing-env not present (section 6 already cleaned up)"
fi

echo
echo "Result: ${PASS} passed, ${FAIL} failed"
[ "${FAIL}" -eq 0 ]
