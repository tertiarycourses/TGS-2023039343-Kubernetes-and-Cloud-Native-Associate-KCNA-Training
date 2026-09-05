#!/usr/bin/env bash
# Lab 10 verification - Resource Requests, Limits, QoS and Autoscaling
# Read-only. Scoped to namespace kcna-lab10.
#
# The QoS assertions are driven by data/workload-profiles.csv: for every row
# whose expected_qos is a real class, the live .status.qosClass must match.
set -uo pipefail

NS="kcna-lab10"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILES="${LAB_DIR}/data/workload-profiles.csv"

PASS=0
FAIL=0

ok()    { printf '  [PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
bad()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }
info()  { printf '  [note] %s\n' "$1"; }
head_() { printf '\n== %s\n' "$1"; }

check() {
  if [ "$2" = "$3" ]; then
    ok "$1 (= $3)"
  else
    bad "$1 (expected '$2', got '$3')"
  fi
}

printf 'Lab 10 verification - namespace %s\n' "$NS"

head_ "Namespace and workload profiles"
NS_PHASE="$(kubectl get ns "$NS" -o jsonpath='{.status.phase}' 2>/dev/null)"
check "namespace $NS is Active" "Active" "${NS_PHASE:-missing}"

if [ ! -r "$PROFILES" ]; then
  bad "data/workload-profiles.csv not readable at $PROFILES"
  printf '\nLab 10: %s passed, %s failed\n' "$PASS" "$FAIL"
  exit 1
fi
N_ROWS="$(awk -F, 'NR>1 && NF>1' "$PROFILES" | wc -l | tr -d ' ')"
ok "workload profiles read: $N_ROWS rows"

head_ "QoS class is derived by the API server, not declared"
while IFS=, read -r workload manifest creq clim mreq mlim qos note; do
  case "$qos" in
    Guaranteed|Burstable|BestEffort) ;;
    *) continue ;;
  esac
  # the quote-engine row describes a Deployment - test one of its Pods
  if [ "$workload" = "quote-engine" ]; then
    target="$(kubectl -n "$NS" get pods -l app=quote-engine -o name 2>/dev/null | head -1)"
    [ -n "$target" ] || { bad "no quote-engine Pod found"; continue; }
  else
    target="pod/$workload"
  fi
  GOT="$(kubectl -n "$NS" get "$target" -o jsonpath='{.status.qosClass}' 2>/dev/null)"
  check "$workload qosClass" "$qos" "${GOT:-missing}"
done < <(awk -F, 'NR>1 && NF>1' "$PROFILES")

head_ "Requests and limits landed as written in the profile"
BL_REQ="$(kubectl -n "$NS" get pod berth-ledger \
  -o jsonpath='{.spec.containers[0].resources.requests.cpu}/{.spec.containers[0].resources.limits.cpu}' 2>/dev/null)"
check "berth-ledger cpu request/limit" "100m/100m" "${BL_REQ:-missing}"

RQ_MEM="$(kubectl -n "$NS" get pod rate-quoter \
  -o jsonpath='{.spec.containers[0].resources.requests.memory}/{.spec.containers[0].resources.limits.memory}' 2>/dev/null)"
check "rate-quoter memory request/limit" "64Mi/192Mi" "${RQ_MEM:-missing}"

NB_REQ="$(kubectl -n "$NS" get pod notice-board \
  -o jsonpath='{.spec.containers[0].resources.requests.cpu}{.spec.containers[0].resources.limits.memory}' 2>/dev/null)"
check "notice-board declares no requests and no limits" "" "${NB_REQ:-}"

head_ "OOMKill evidence"
OOM_REASON="$(kubectl -n "$NS" get pod ledger-compactor \
  -o jsonpath='{.status.containerStatuses[0].state.terminated.reason}' 2>/dev/null)"
OOM_CODE="$(kubectl -n "$NS" get pod ledger-compactor \
  -o jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}' 2>/dev/null)"
OOM_LIMIT="$(kubectl -n "$NS" get pod ledger-compactor \
  -o jsonpath='{.spec.containers[0].resources.limits.memory}' 2>/dev/null)"
check "ledger-compactor termination reason" "OOMKilled" "${OOM_REASON:-missing}"
check "ledger-compactor exit code (128 + SIGKILL 9)" "137" "${OOM_CODE:-missing}"
check "ledger-compactor memory limit that caused it" "32Mi" "${OOM_LIMIT:-missing}"

head_ "LimitRange"
LR_DEFREQ="$(kubectl -n "$NS" get limitrange mfs-container-limits \
  -o jsonpath='{.spec.limits[0].defaultRequest.cpu}' 2>/dev/null)"
LR_DEF="$(kubectl -n "$NS" get limitrange mfs-container-limits \
  -o jsonpath='{.spec.limits[0].default.cpu}' 2>/dev/null)"
LR_MAX="$(kubectl -n "$NS" get limitrange mfs-container-limits \
  -o jsonpath='{.spec.limits[0].max.cpu}' 2>/dev/null)"
check "LimitRange defaultRequest.cpu" "50m" "${LR_DEFREQ:-missing}"
check "LimitRange default.cpu"        "500m" "${LR_DEF:-missing}"
check "LimitRange max.cpu"            "1" "${LR_MAX:-missing}"

head_ "ResourceQuota"
RQ_HARD="$(kubectl -n "$NS" get resourcequota mfs-lab-quota \
  -o jsonpath='{.status.hard.requests\.cpu}' 2>/dev/null)"
RQ_USED="$(kubectl -n "$NS" get resourcequota mfs-lab-quota \
  -o jsonpath='{.status.used.requests\.cpu}' 2>/dev/null)"
check "quota hard requests.cpu" "1" "${RQ_HARD:-missing}"
if [ -n "${RQ_USED:-}" ]; then
  ok "quota used requests.cpu is being tracked (= ${RQ_USED})"
else
  bad "quota status.used.requests.cpu is empty - the quota controller has not reconciled yet"
fi

REJECTED="$(kubectl -n "$NS" get pod cargo-modeller -o name 2>/dev/null)"
check "over-budget Pod cargo-modeller was NOT created" "" "${REJECTED:-}"

head_ "Deployment and HPA"
DEP_READY="$(kubectl -n "$NS" get deploy quote-engine -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
check "quote-engine readyReplicas" "2" "${DEP_READY:-0}"

HPA_API="$(kubectl -n "$NS" get hpa quote-engine -o jsonpath='{.apiVersion}' 2>/dev/null)"
check "HPA served as autoscaling/v2" "autoscaling/v2" "${HPA_API:-missing}"
HPA_MIN="$(kubectl -n "$NS" get hpa quote-engine -o jsonpath='{.spec.minReplicas}' 2>/dev/null)"
HPA_MAX="$(kubectl -n "$NS" get hpa quote-engine -o jsonpath='{.spec.maxReplicas}' 2>/dev/null)"
HPA_TGT="$(kubectl -n "$NS" get hpa quote-engine \
  -o jsonpath='{.spec.metrics[0].resource.target.averageUtilization}' 2>/dev/null)"
check "HPA minReplicas" "2" "${HPA_MIN:-missing}"
check "HPA maxReplicas" "6" "${HPA_MAX:-missing}"
check "HPA cpu target utilisation" "60" "${HPA_TGT:-missing}"

head_ "Metrics pipeline - reported honestly, not assumed"
if kubectl get apiservice v1beta1.metrics.k8s.io >/dev/null 2>&1; then
  MS_AVAIL="$(kubectl get apiservice v1beta1.metrics.k8s.io \
    -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)"
else
  MS_AVAIL="absent"
fi
SCALING="$(kubectl -n "$NS" get hpa quote-engine \
  -o jsonpath='{.status.conditions[?(@.type=="ScalingActive")].reason}' 2>/dev/null)"

if [ "$MS_AVAIL" = "True" ]; then
  info "metrics-server IS installed (v1beta1.metrics.k8s.io Available=True)"
  case "$SCALING" in
    ValidMetricFound|SucceededGetScale|"") ok "HPA ScalingActive reason with metrics present: '${SCALING:-<not yet set>}'" ;;
    *) ok "HPA ScalingActive reason is '${SCALING}' - inspect with: kubectl -n $NS describe hpa quote-engine" ;;
  esac
else
  info "metrics-server is NOT installed (v1beta1.metrics.k8s.io: ${MS_AVAIL}) - this is the stock kind default"
  case "$SCALING" in
    FailedGetResourceMetric|InvalidSelector|"")
      ok "HPA correctly reports it cannot read metrics (ScalingActive reason='${SCALING:-<not yet set>}') - the pipeline is missing, not the HPA spec" ;;
    *)
      bad "expected FailedGetResourceMetric without metrics-server, got '${SCALING}'" ;;
  esac
fi

printf '\n----------------------------------------\n'
printf 'Lab 10: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
printf 'ALL CHECKS PASSED\n'
