#!/usr/bin/env bash
# Lab 07 verification - Deployments, Rollout Strategy and Rollback
# Read-only: it creates and deletes nothing. Scoped to namespace kcna-lab07.
set -uo pipefail

NS="kcna-lab07"
DEP="freight-portal"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAN="${LAB_DIR}/data/release-plan.csv"

PASS=0
FAIL=0

ok()    { printf '  [PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
bad()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }
head_() { printf '\n== %s\n' "$1"; }

check() {
  if [ "$2" = "$3" ]; then
    ok "$1 (= $3)"
  else
    bad "$1 (expected '$2', got '$3')"
  fi
}

printf 'Lab 07 verification - namespace %s\n' "$NS"

head_ "Namespace and dataset"
NS_PHASE="$(kubectl get ns "$NS" -o jsonpath='{.status.phase}' 2>/dev/null)"
check "namespace $NS is Active" "Active" "${NS_PHASE:-missing}"

if [ -r "$PLAN" ]; then
  WANT_REPLICAS="$(awk -F, '$2=="r24.2" {print $5}' "$PLAN")"
  WANT_SURGE="$(awk -F, '$2=="r24.2" {print $6}' "$PLAN")"
  WANT_UNAVAIL="$(awk -F, '$2=="r24.2" {print $7}' "$PLAN")"
  WANT_MAXPODS="$(awk -F, '$2=="r24.2" {print $8}' "$PLAN")"
  WANT_MINAVAIL="$(awk -F, '$2=="r24.2" {print $9}' "$PLAN")"
  ok "release plan read: r24.2 wants replicas=$WANT_REPLICAS surge=$WANT_SURGE unavailable=$WANT_UNAVAIL (ceiling $WANT_MAXPODS / floor $WANT_MINAVAIL)"
else
  bad "data/release-plan.csv not readable at $PLAN"
  WANT_REPLICAS=4; WANT_SURGE=1; WANT_UNAVAIL=0; WANT_MAXPODS=5; WANT_MINAVAIL=4
fi

head_ "Deployment shape matches the release plan"
GOT_REPLICAS="$(kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.replicas}' 2>/dev/null)"
GOT_SURGE="$(kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.strategy.rollingUpdate.maxSurge}' 2>/dev/null)"
GOT_UNAVAIL="$(kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.strategy.rollingUpdate.maxUnavailable}' 2>/dev/null)"
GOT_STRATEGY="$(kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.strategy.type}' 2>/dev/null)"
GOT_HISTLIMIT="$(kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.revisionHistoryLimit}' 2>/dev/null)"
check "strategy type" "RollingUpdate" "${GOT_STRATEGY:-missing}"
check "spec.replicas" "$WANT_REPLICAS" "${GOT_REPLICAS:-missing}"
check "maxSurge" "$WANT_SURGE" "${GOT_SURGE:-missing}"
check "maxUnavailable" "$WANT_UNAVAIL" "${GOT_UNAVAIL:-missing}"
check "revisionHistoryLimit" "3" "${GOT_HISTLIMIT:-missing}"

head_ "Rollback landed on the good release (r24.2)"
GOT_IMAGE="$(kubectl -n "$NS" get deploy "$DEP" \
  -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)"
check "current image" "nginx:1.27-alpine" "${GOT_IMAGE:-missing}"

GOT_RELEASE="$(kubectl -n "$NS" get deploy "$DEP" \
  -o jsonpath='{.spec.template.metadata.labels.release}' 2>/dev/null)"
check "template release label" "r24.2" "${GOT_RELEASE:-missing}"

GOT_CM="$(kubectl -n "$NS" get deploy "$DEP" \
  -o jsonpath='{.spec.template.spec.volumes[0].configMap.name}' 2>/dev/null)"
check "mounted ConfigMap" "portal-site-r24-2" "${GOT_CM:-missing}"

head_ "Availability"
READY="$(kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
AVAIL="$(kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.status.availableReplicas}' 2>/dev/null)"
UPD="$(kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.status.updatedReplicas}' 2>/dev/null)"
check "readyReplicas"   "$WANT_REPLICAS" "${READY:-0}"
check "availableReplicas" "$WANT_REPLICAS" "${AVAIL:-0}"
check "updatedReplicas"   "$WANT_REPLICAS" "${UPD:-0}"

PROG="$(kubectl -n "$NS" get deploy "$DEP" \
  -o jsonpath='{.status.conditions[?(@.type=="Progressing")].reason}' 2>/dev/null)"
check "Progressing condition reason" "NewReplicaSetAvailable" "${PROG:-missing}"

head_ "Served content comes from data/site-r24.2.html"
SERVED="$(kubectl -n "$NS" exec "deploy/$DEP" -c web -- \
  grep -o 'RELEASE=r24\.[0-9]' /usr/share/nginx/html/index.html 2>/dev/null | head -1)"
check "page served by a live Pod" "RELEASE=r24.2" "${SERVED:-missing}"

head_ "ReplicaSet generations retained"
RS_TOTAL="$(kubectl -n "$NS" get rs -l app="$DEP" --no-headers 2>/dev/null | wc -l | tr -d ' ')"
if [ "${RS_TOTAL:-0}" -ge 2 ] && [ "${RS_TOTAL:-0}" -le 4 ]; then
  ok "between 2 and 4 ReplicaSets retained under revisionHistoryLimit=3 (found $RS_TOTAL)"
else
  bad "expected 2-4 retained ReplicaSets, found ${RS_TOTAL:-0}"
fi

RS_ACTIVE="$(kubectl -n "$NS" get rs -l app="$DEP" \
  -o jsonpath='{range .items[?(@.spec.replicas>0)]}{.metadata.name}{"\n"}{end}' 2>/dev/null | wc -l | tr -d ' ')"
check "exactly one ReplicaSet is scaled above zero" "1" "${RS_ACTIVE:-0}"

head_ "Service front door"
SVC_TYPE="$(kubectl -n "$NS" get svc "$DEP" -o jsonpath='{.spec.type}' 2>/dev/null)"
check "Service type" "ClusterIP" "${SVC_TYPE:-missing}"
EPS="$(kubectl -n "$NS" get endpointslices -l "kubernetes.io/service-name=$DEP" \
  -o jsonpath='{range .items[*]}{range .endpoints[*]}{.addresses[0]}{"\n"}{end}{end}' 2>/dev/null | grep -c . )"
check "EndpointSlice backend addresses" "$WANT_REPLICAS" "${EPS:-0}"

printf '\n----------------------------------------\n'
printf 'Lab 07: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
printf 'ALL CHECKS PASSED\n'
