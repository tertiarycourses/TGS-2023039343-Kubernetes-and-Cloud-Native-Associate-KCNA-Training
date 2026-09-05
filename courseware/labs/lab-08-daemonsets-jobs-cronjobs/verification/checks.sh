#!/usr/bin/env bash
# Lab 08 verification - DaemonSets, Jobs and CronJobs
# Read-only. Scoped to namespace kcna-lab08.
set -uo pipefail

NS="kcna-lab08"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
READINGS="${LAB_DIR}/data/berth-readings.csv"
QUEUE="${LAB_DIR}/data/manifest-queue.txt"
TARIFFS="${LAB_DIR}/data/tariff-rates.csv"

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

printf 'Lab 08 verification - namespace %s\n' "$NS"

head_ "Namespace and datasets"
NS_PHASE="$(kubectl get ns "$NS" -o jsonpath='{.status.phase}' 2>/dev/null)"
check "namespace $NS is Active" "Active" "${NS_PHASE:-missing}"

if [ -r "$READINGS" ] && [ -r "$QUEUE" ] && [ -r "$TARIFFS" ]; then
  N_BERTHS="$(awk -F, 'NR>1 {b[$2]=1} END {n=0; for (k in b) n++; print n}' "$READINGS")"
  N_HIGH="$(awk -F, 'NR>1 && $5+0 >= 90 {n++} END {print n+0}' "$READINGS")"
  N_QUEUE="$(grep -c . "$QUEUE")"
  N_REVIEW="$(awk -F, 'NR>1 && $4=="review" {n++} END {print n+0}' "$TARIFFS")"
  ok "datasets read: $N_BERTHS berths ($N_HIGH high-occupancy), $N_QUEUE queue items, $N_REVIEW tariff lanes under review"
else
  bad "one or more data files are unreadable under ${LAB_DIR}/data"
  N_BERTHS=8; N_HIGH=3; N_QUEUE=6; N_REVIEW=2
fi

CM_KEYS="$(kubectl -n "$NS" get configmap berth-data \
  -o go-template='{{range $k,$v := .data}}{{$k}}{{"\n"}}{{end}}' 2>/dev/null | grep -c .)"
if [ "${CM_KEYS:-0}" -ge 3 ]; then
  ok "ConfigMap berth-data carries all three data files"
else
  bad "ConfigMap berth-data does not carry three data keys (found ${CM_KEYS:-0})"
fi

head_ "DaemonSet berth-agent (one Pod per node)"
NODES="$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"
ok "cluster has $NODES schedulable node(s) - a DaemonSet must produce exactly that many Pods"
DS_DESIRED="$(kubectl -n "$NS" get ds berth-agent -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)"
DS_READY="$(kubectl -n "$NS" get ds berth-agent -o jsonpath='{.status.numberReady}' 2>/dev/null)"
check "desiredNumberScheduled equals the node count" "$NODES" "${DS_DESIRED:-0}"
check "numberReady equals the node count"            "$NODES" "${DS_READY:-0}"

DS_HAS_REPLICAS="$(kubectl -n "$NS" get ds berth-agent -o jsonpath='{.spec.replicas}' 2>/dev/null)"
check "a DaemonSet has no .spec.replicas field" "" "${DS_HAS_REPLICAS:-}"

DS_POD="$(kubectl -n "$NS" get pods -l app=berth-agent -o name 2>/dev/null | head -1)"
DS_LOG="$(kubectl -n "$NS" logs "${DS_POD:-pod/none}" --tail=5 2>/dev/null)"
DS_SEEN="$(printf '%s\n' "$DS_LOG" | grep -o "berths=${N_BERTHS} high_occupancy=${N_HIGH}" | head -1)"
check "agent log reports the dataset it read" "berths=${N_BERTHS} high_occupancy=${N_HIGH}" "${DS_SEEN:-none}"

head_ "Indexed Job manifest-reconcile"
J_MODE="$(kubectl -n "$NS" get job manifest-reconcile -o jsonpath='{.spec.completionMode}' 2>/dev/null)"
J_COMP="$(kubectl -n "$NS" get job manifest-reconcile -o jsonpath='{.spec.completions}' 2>/dev/null)"
J_PAR="$(kubectl -n "$NS" get job manifest-reconcile -o jsonpath='{.spec.parallelism}' 2>/dev/null)"
J_SUCC="$(kubectl -n "$NS" get job manifest-reconcile -o jsonpath='{.status.succeeded}' 2>/dev/null)"
check "completionMode" "Indexed" "${J_MODE:-missing}"
check "completions matches the queue length" "$N_QUEUE" "${J_COMP:-0}"
check "parallelism" "2" "${J_PAR:-0}"
check "succeeded Pods" "$N_QUEUE" "${J_SUCC:-0}"

J_COND="$(kubectl -n "$NS" get job manifest-reconcile \
  -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)"
check "Job condition Complete" "True" "${J_COND:-missing}"

J_IDX="$(kubectl -n "$NS" get pods -l job-name=manifest-reconcile \
  -o jsonpath='{range .items[*]}{.metadata.annotations.batch\.kubernetes\.io/job-completion-index}{"\n"}{end}' 2>/dev/null \
  | grep -c .)"
check "one Pod per completion index" "$N_QUEUE" "${J_IDX:-0}"

RECONCILED="$(kubectl -n "$NS" logs -l job-name=manifest-reconcile --tail=-1 2>/dev/null \
  | grep -c 'RECONCILED MFS-MAN-')"
check "distinct work items reported RECONCILED" "$N_QUEUE" "${RECONCILED:-0}"

head_ "CronJob tariff-sync"
CJ_SCHED="$(kubectl -n "$NS" get cronjob tariff-sync -o jsonpath='{.spec.schedule}' 2>/dev/null)"
CJ_CONC="$(kubectl -n "$NS" get cronjob tariff-sync -o jsonpath='{.spec.concurrencyPolicy}' 2>/dev/null)"
CJ_HIST="$(kubectl -n "$NS" get cronjob tariff-sync -o jsonpath='{.spec.successfulJobsHistoryLimit}' 2>/dev/null)"
check "schedule" "*/2 * * * *" "${CJ_SCHED:-missing}"
check "concurrencyPolicy" "Forbid" "${CJ_CONC:-missing}"
check "successfulJobsHistoryLimit" "3" "${CJ_HIST:-missing}"

CJ_JOBS="$(kubectl -n "$NS" get jobs -l app=tariff-sync --no-headers 2>/dev/null | wc -l | tr -d ' ')"
if [ "${CJ_JOBS:-0}" -ge 1 ] && [ "${CJ_JOBS:-0}" -le 3 ]; then
  ok "CronJob has spawned $CJ_JOBS Job(s), within successfulJobsHistoryLimit=3"
else
  bad "expected 1-3 retained tariff-sync Jobs, found ${CJ_JOBS:-0} (wait for the next 2-minute boundary)"
fi

CJ_LOG="$(kubectl -n "$NS" logs -l app=tariff-sync --tail=-1 2>/dev/null)"
case "$CJ_LOG" in
  *SYNC-OK*) ok "a tariff-sync run printed SYNC-OK" ;;
  *) bad "no tariff-sync run has printed SYNC-OK yet" ;;
esac
CJ_FLAG="$(printf '%s\n' "$CJ_LOG" | grep -c '^FLAGGED ')"
if [ "${CJ_FLAG:-0}" -ge "$N_REVIEW" ]; then
  ok "tariff-sync flagged the lanes marked 'review' in tariff-rates.csv (>=$N_REVIEW lines, found $CJ_FLAG)"
else
  bad "expected at least $N_REVIEW FLAGGED lines from tariff-rates.csv, found ${CJ_FLAG:-0}"
fi

head_ "Failure injection: customs-export exceeded its backoffLimit"
BJ_FAIL="$(kubectl -n "$NS" get job customs-export \
  -o jsonpath='{.status.conditions[?(@.type=="Failed")].reason}' 2>/dev/null)"
if [ -z "${BJ_FAIL:-}" ]; then
  ok "customs-export Job not present - failure injection is optional, section 6 skipped"
else
  check "customs-export failure reason" "BackoffLimitExceeded" "$BJ_FAIL"
  BJ_TRIES="$(kubectl -n "$NS" get job customs-export -o jsonpath='{.status.failed}' 2>/dev/null)"
  check "failed Pod attempts (1 initial + backoffLimit 2)" "3" "${BJ_TRIES:-0}"
fi

printf '\n----------------------------------------\n'
printf 'Lab 08: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
printf 'ALL CHECKS PASSED\n'
