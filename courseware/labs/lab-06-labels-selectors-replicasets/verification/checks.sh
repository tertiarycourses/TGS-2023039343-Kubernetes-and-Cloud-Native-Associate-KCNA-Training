#!/usr/bin/env bash
# Lab 06 verification - Labels, Selectors and ReplicaSets
# Read-only. Scoped entirely to namespace kcna-lab06.
set -uo pipefail

NS="kcna-lab06"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA="${LAB_DIR}/data/service-inventory.csv"

PASS=0
FAIL=0

ok()   { printf '  [PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }
head_() { printf '\n== %s\n' "$1"; }

check() {
  # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    ok "$1 (= $3)"
  else
    bad "$1 (expected '$2', got '$3')"
  fi
}

printf 'Lab 06 verification - namespace %s\n' "$NS"

head_ "Namespace"
NS_PHASE="$(kubectl get ns "$NS" -o jsonpath='{.status.phase}' 2>/dev/null)"
check "namespace $NS is Active" "Active" "${NS_PHASE:-missing}"

head_ "ConfigMap built from data/service-inventory.csv"
CM_KEY="$(kubectl -n "$NS" get configmap service-inventory \
  -o jsonpath='{.data.service-inventory\.csv}' 2>/dev/null | head -c 12)"
check "configmap service-inventory carries the CSV header" "service_name" "${CM_KEY:-missing}"

if [ -r "$DATA" ]; then
  EDGE_EXPECTED="$(awk -F, 'NR>1 && $3=="edge"' "$DATA" | wc -l | tr -d ' ')"
  ok "data file present, $EDGE_EXPECTED edge-tier services declared in the inventory"
else
  bad "data/service-inventory.csv not readable at $DATA"
  EDGE_EXPECTED="?"
fi

head_ "ReplicaSet tracking-api (matchLabels)"
RS_DESIRED="$(kubectl -n "$NS" get rs tracking-api -o jsonpath='{.spec.replicas}' 2>/dev/null)"
RS_READY="$(kubectl -n "$NS" get rs tracking-api -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
check "tracking-api desired replicas" "3" "${RS_DESIRED:-missing}"
check "tracking-api ready replicas"   "3" "${RS_READY:-0}"

SEL_APP="$(kubectl -n "$NS" get rs tracking-api \
  -o jsonpath='{.spec.selector.matchLabels.app}' 2>/dev/null)"
check "tracking-api selector matchLabels.app" "tracking-api" "${SEL_APP:-missing}"

head_ "Adoption: the hand-created Pod is owned by the ReplicaSet"
OWNER="$(kubectl -n "$NS" get pod tracking-api-legacy \
  -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null)"
OWNER_KIND="$(kubectl -n "$NS" get pod tracking-api-legacy \
  -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null)"
if [ "${OWNER:-}" = "tracking-api" ] && [ "${OWNER_KIND:-}" = "ReplicaSet" ]; then
  ok "tracking-api-legacy adopted by ReplicaSet/tracking-api"
elif [ -z "${OWNER:-}" ]; then
  ok "tracking-api-legacy has no ownerReferences - it was orphaned by the relabel step (also a valid end state)"
else
  bad "tracking-api-legacy owner is '${OWNER_KIND:-none}/${OWNER:-none}', expected ReplicaSet/tracking-api or none"
fi

head_ "Selector arithmetic"
N_EDGE="$(kubectl -n "$NS" get pods -l 'app=tracking-api,tier=edge' \
  --no-headers 2>/dev/null | wc -l | tr -d ' ')"
if [ "${N_EDGE:-0}" -ge 3 ]; then
  ok "at least 3 Pods match -l app=tracking-api,tier=edge (found $N_EDGE)"
else
  bad "expected >=3 Pods matching app=tracking-api,tier=edge, found ${N_EDGE:-0}"
fi

N_SETBASED="$(kubectl -n "$NS" get pods \
  -l 'app in (tracking-api,berth-status),tier notin (experimental)' \
  --no-headers 2>/dev/null | wc -l | tr -d ' ')"
if [ "${N_SETBASED:-0}" -ge 5 ]; then
  ok "set-based selector returns >=5 Pods (found $N_SETBASED)"
else
  bad "set-based selector returned ${N_SETBASED:-0}, expected >=5"
fi

head_ "ReplicaSet berth-status (matchExpressions)"
BS_READY="$(kubectl -n "$NS" get rs berth-status -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
check "berth-status ready replicas" "2" "${BS_READY:-0}"
N_EXPR="$(kubectl -n "$NS" get rs berth-status \
  -o jsonpath='{.spec.selector.matchExpressions[*].operator}' 2>/dev/null)"
case "$N_EXPR" in
  *NotIn*Exists*In*|*In*NotIn*Exists*|*NotIn*In*Exists*)
    ok "berth-status selector uses NotIn, Exists and In ($N_EXPR)" ;;
  *) bad "berth-status matchExpressions operators were '$N_EXPR'" ;;
esac

head_ "Data-driven audit Pod"
AUDIT_PHASE="$(kubectl -n "$NS" get pod label-audit -o jsonpath='{.status.phase}' 2>/dev/null)"
check "label-audit Pod phase" "Succeeded" "${AUDIT_PHASE:-missing}"
AUDIT_LOG="$(kubectl -n "$NS" logs label-audit 2>/dev/null)"
case "$AUDIT_LOG" in
  *AUDIT-COMPLETE*) ok "label-audit printed AUDIT-COMPLETE" ;;
  *) bad "label-audit log did not contain AUDIT-COMPLETE" ;;
esac
AUDIT_EDGE="$(printf '%s\n' "$AUDIT_LOG" | grep -Ec ' app=[^ ]+ tier=edge( |$)' 2>/dev/null)"
check "audit Pod listed the edge services from the CSV" "$EDGE_EXPECTED" "${AUDIT_EDGE:-0}"

printf '\n----------------------------------------\n'
printf 'Lab 06: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
printf 'ALL CHECKS PASSED\n'
