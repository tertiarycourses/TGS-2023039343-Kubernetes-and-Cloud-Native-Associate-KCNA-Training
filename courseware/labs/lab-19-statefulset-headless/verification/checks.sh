#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Lab 19 — StatefulSets, Headless Services and Stable Identity
# Graded verification. READ-ONLY: never creates, mutates or deletes anything.
#
# Run AFTER Step 10 (statefulset back at 3 replicas, ledger-client running,
# lane-indexer up) and BEFORE Section 8 cleanup.
#
#   usage:  bash verification/checks.sh
#   env:    KUBECTL=/path/to/kubectl   (default: kubectl)
#           NS=kcna-lab19              (default: kcna-lab19)
# ---------------------------------------------------------------------------
set -uo pipefail

KUBECTL="${KUBECTL:-kubectl}"
NS="${NS:-kcna-lab19}"
STS="depot-ledger"
SVC="depot-ledger"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0
pass() { printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }
check() { if [ "$1" = "0" ]; then pass "$2"; else fail "$2"; fi; }
jp() { "$KUBECTL" "$@" 2>/dev/null || true; }

printf '== Lab 19 verification — namespace %s ==\n' "$NS"

if ! command -v "$KUBECTL" >/dev/null 2>&1; then
  printf '[FAIL] kubectl not found on PATH (set KUBECTL=/path/to/kubectl)\n'
  exit 2
fi

if ! "$KUBECTL" get namespace "$NS" >/dev/null 2>&1; then
  fail "namespace $NS exists"
  printf -- '------------------------------------------------\n'
  printf '%d passed, %d failed\n' "$PASS" "$FAIL"
  exit 1
fi
pass "namespace $NS exists"

# --- 1. headless vs ClusterIP ----------------------------------------------
HL_IP="$(jp -n "$NS" get svc "$SVC" -o jsonpath='{.spec.clusterIP}')"
if [ "$HL_IP" = "None" ]; then
  pass "service/$SVC is headless (clusterIP: None)"
else
  fail "service/$SVC should have clusterIP None (saw '$HL_IP')"
fi

VIP="$(jp -n "$NS" get svc depot-ledger-vip -o jsonpath='{.spec.clusterIP}')"
case "$VIP" in
  ""|None) fail "service/depot-ledger-vip should have a real ClusterIP (saw '$VIP')" ;;
  *)       pass "service/depot-ledger-vip has an allocated ClusterIP" ;;
esac

# --- 2. StatefulSet identity wiring ----------------------------------------
STS_SVC="$(jp -n "$NS" get statefulset "$STS" -o jsonpath='{.spec.serviceName}')"
if [ "$STS_SVC" = "$SVC" ]; then
  pass "statefulset/$STS has serviceName=$SVC"
else
  fail "statefulset/$STS serviceName should be $SVC (saw '$STS_SVC')"
fi

RDY="$(jp -n "$NS" get statefulset "$STS" -o jsonpath='{.status.readyReplicas}')"
if [ "${RDY:-0}" = "3" ]; then
  pass "statefulset/$STS reports 3/3 ready replicas"
else
  fail "statefulset/$STS should report 3 ready replicas (saw '${RDY:-0}')"
fi

MISSING_POD=0
for i in 0 1 2; do
  "$KUBECTL" -n "$NS" get pod "${STS}-${i}" >/dev/null 2>&1 || MISSING_POD=1
done
check "$MISSING_POD" "pods are named by ordinal: ${STS}-0, -1, -2"

# --- 3. volumeClaimTemplates ------------------------------------------------
MISSING_PVC=0
for i in 0 1 2; do
  "$KUBECTL" -n "$NS" get pvc "ledger-${STS}-${i}" >/dev/null 2>&1 || MISSING_PVC=1
done
check "$MISSING_PVC" "one PVC exists per ordinal from volumeClaimTemplates"

WRONG_CLAIM=0
for i in 0 1 2; do
  CLAIM="$(jp -n "$NS" get pod "${STS}-${i}" \
    -o jsonpath='{.spec.volumes[?(@.name=="ledger")].persistentVolumeClaim.claimName}')"
  [ "$CLAIM" = "ledger-${STS}-${i}" ] || WRONG_CLAIM=1
done
check "$WRONG_CLAIM" "each pod mounts its own ordinal's PVC"

# --- 4. the dataset genuinely drove per-ordinal content ---------------------
SHARD_OK=0
for i in 0 1 2; do
  EXPECTED="$(grep -c ",shard-${i}," "$LAB_DIR/data/ledger-entries.csv" 2>/dev/null || echo -1)"
  SERVED="$(jp -n "$NS" exec "${STS}-${i}" -c web -- \
    cat /usr/share/nginx/html/index.html | sed -n 's:.*shard_entries: \([0-9]*\).*:\1:p')"
  [ "$SERVED" = "$EXPECTED" ] || SHARD_OK=1
done
check "$SHARD_OK" "shard entry counts 9/8/7 match data/ledger-entries.csv"

# --- 5. per-pod DNS ---------------------------------------------------------
FQDN="${STS}-1.${SVC}.${NS}.svc.cluster.local"
"$KUBECTL" -n "$NS" exec ledger-client -- nslookup "$FQDN" >/dev/null 2>&1
check $? "per-pod DNS resolves $FQDN"

# busybox nslookup prints the resolver's own address alongside the answers,
# and its exact line formatting varies by build. Extract every IPv4 literal,
# drop the resolver's address, and count what is left.
DNS_IP="$(jp -n "$NS" exec ledger-client -- \
  sh -c "grep '^nameserver' /etc/resolv.conf | head -1 | cut -d' ' -f2" | tr -d '\r')"
resolved_count() {
  jp -n "$NS" exec ledger-client -- nslookup "$1" \
    | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' \
    | grep -v "^${DNS_IP:-0.0.0.0}$" \
    | sort -u | grep -c '' || true
}
HL_N="$(resolved_count "${SVC}.${NS}.svc.cluster.local")"
VIP_N="$(resolved_count "depot-ledger-vip.${NS}.svc.cluster.local")"
if [ "${HL_N:-0}" -eq 3 ] && [ "${VIP_N:-0}" -eq 1 ]; then
  pass "headless DNS returns 3 pod addresses, VIP DNS returns 1"
else
  fail "expected headless=3 vip=1 resolved addresses (saw ${HL_N}/${VIP_N})"
fi

# --- 6. the volume was reattached, not recreated ---------------------------
MOUNTS="$(jp -n "$NS" exec "${STS}-1" -c web -- \
  grep -c '^mounted ' /usr/share/nginx/html/mounts.log)"
if [ -n "$MOUNTS" ] && [ "$MOUNTS" -ge 2 ] 2>/dev/null; then
  pass "${STS}-1 reattached its original volume (mount count ${MOUNTS})"
else
  fail "${STS}-1 mounts.log should hold 2+ records after Step 7 (saw '${MOUNTS:-0}')"
fi

# --- 7. retention policy is explicit and safe ------------------------------
WD="$(jp -n "$NS" get statefulset "$STS" \
  -o jsonpath='{.spec.persistentVolumeClaimRetentionPolicy.whenDeleted}')"
WS="$(jp -n "$NS" get statefulset "$STS" \
  -o jsonpath='{.spec.persistentVolumeClaimRetentionPolicy.whenScaled}')"
if [ "$WD" = "Retain" ] && [ "$WS" = "Retain" ]; then
  pass "persistentVolumeClaimRetentionPolicy is Retain/Retain"
else
  fail "expected Retain/Retain retention policy (saw '$WD'/'$WS')"
fi

# --- 8. parallel pod management --------------------------------------------
PMP="$(jp -n "$NS" get statefulset lane-indexer -o jsonpath='{.spec.podManagementPolicy}')"
if [ "$PMP" = "Parallel" ]; then
  pass "statefulset/lane-indexer uses podManagementPolicy=Parallel"
else
  fail "statefulset/lane-indexer should use Parallel (saw '$PMP')"
fi

# --- 9. safety gate ---------------------------------------------------------
PRIV="$(jp -n "$NS" get pods \
  -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.securityContext.privileged}{"\n"}{end}{end}' \
  | grep -c '^true$' || true)"
if [ "${PRIV:-0}" = "0" ]; then
  pass "no container in $NS requests privileged: true"
else
  fail "$PRIV privileged container(s) found in $NS — this lab must not need any"
fi

printf -- '------------------------------------------------\n'
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
