#!/usr/bin/env bash
# Lab 09 verification - Scheduling: nodeSelector, Affinity, Taints, Tolerations
# Read-only. Asserts against namespace kcna-lab09 and the labels/taint the
# learner applied to the single node. It changes nothing.
#
# Run this at the END of section 6 (taint still applied, before Cleanup).
set -uo pipefail

NS="kcna-lab09"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY="${LAB_DIR}/data/node-placement-policy.csv"

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

printf 'Lab 09 verification - namespace %s\n' "$NS"

head_ "Namespace and placement policy"
NS_PHASE="$(kubectl get ns "$NS" -o jsonpath='{.status.phase}' 2>/dev/null)"
check "namespace $NS is Active" "Active" "${NS_PHASE:-missing}"

if [ ! -r "$POLICY" ]; then
  bad "data/node-placement-policy.csv not readable at $POLICY - cannot drive the remaining checks"
  printf '\nLab 09: %s passed, %s failed\n' "$PASS" "$FAIL"
  exit 1
fi
N_ROWS="$(awk -F, 'NR>1 && NF>1' "$POLICY" | wc -l | tr -d ' ')"
ok "placement policy read: $N_ROWS workload rows"

head_ "Cluster shape"
NODE_COUNT="$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"
NODE="$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
ok "cluster has $NODE_COUNT node(s); first node is ${NODE:-unknown}"

head_ "Node labels required by the policy (apply_label=yes)"
while IFS=, read -r workload manifest mechanism lkey lval apply tkey tval teff phase; do
  [ "$apply" = "yes" ] || continue
  # bracket notation needs no dot-escaping in kubectl jsonpath
  GOT="$(kubectl get node "$NODE" -o jsonpath="{.metadata.labels['${lkey}']}" 2>/dev/null)"
  check "node label $lkey (needed by $workload)" "$lval" "${GOT:-missing}"
done < <(awk -F, 'NR>1 && NF>1' "$POLICY")

head_ "Node taint applied for the maintenance-window exercise"
TAINT="$(kubectl get node "$NODE" \
  -o jsonpath='{range .spec.taints[*]}{.key}={.value}:{.effect}{"\n"}{end}' 2>/dev/null \
  | grep '^mfs.io/maintenance=')"
check "taint on $NODE" "mfs.io/maintenance=window:NoSchedule" "${TAINT:-none}"

head_ "Pod placement outcomes match the policy"
while IFS=, read -r workload manifest mechanism lkey lval apply tkey tval teff phase; do
  GOT_PHASE="$(kubectl -n "$NS" get pod "$workload" -o jsonpath='{.status.phase}' 2>/dev/null)"
  check "$workload ($mechanism) phase" "$phase" "${GOT_PHASE:-missing}"
done < <(awk -F, 'NR>1 && NF>1' "$POLICY")

head_ "Scheduled Pods really landed on the node"
for w in gate-scanner manifest-store eta-predictor crane-controller; do
  ON="$(kubectl -n "$NS" get pod "$w" -o jsonpath='{.spec.nodeName}' 2>/dev/null)"
  check "$w scheduled onto $NODE" "$NODE" "${ON:-unscheduled}"
done

head_ "Pending Pods have no nodeName and a FailedScheduling event"
for w in draft-optimiser yard-report; do
  ON="$(kubectl -n "$NS" get pod "$w" -o jsonpath='{.spec.nodeName}' 2>/dev/null)"
  check "$w has no assigned node" "" "${ON:-}"
  REASON="$(kubectl -n "$NS" get pod "$w" \
    -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")].reason}' 2>/dev/null)"
  check "$w PodScheduled reason" "Unschedulable" "${REASON:-missing}"
  EV="$(kubectl -n "$NS" get events --field-selector "involvedObject.name=$w,reason=FailedScheduling" \
    -o jsonpath='{.items[0].message}' 2>/dev/null)"
  if [ -n "${EV:-}" ]; then
    ok "$w has a FailedScheduling event: ${EV}"
  else
    bad "$w has no FailedScheduling event (events expire after ~1h - re-create the Pod to regenerate one)"
  fi
done

head_ "Mechanism is declared where the policy says it should be"
GS_SEL="$(kubectl -n "$NS" get pod gate-scanner \
  -o jsonpath='{.spec.nodeSelector.mfs\.io/zone}' 2>/dev/null)"
check "gate-scanner nodeSelector mfs.io/zone" "sg-harbourfront" "${GS_SEL:-missing}"

MS_OP="$(kubectl -n "$NS" get pod manifest-store \
  -o jsonpath='{.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[*].operator}' 2>/dev/null)"
check "manifest-store required affinity operators" "In DoesNotExist" "${MS_OP:-missing}"

EP_W="$(kubectl -n "$NS" get pod eta-predictor \
  -o jsonpath='{.spec.affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution[*].weight}' 2>/dev/null)"
check "eta-predictor preference weights" "80 20" "${EP_W:-missing}"

CC_TOL="$(kubectl -n "$NS" get pod crane-controller \
  -o jsonpath='{.spec.tolerations[?(@.key=="mfs.io/maintenance")].effect}' 2>/dev/null)"
check "crane-controller tolerates NoSchedule" "NoSchedule" "${CC_TOL:-missing}"

printf '\n----------------------------------------\n'
printf 'Lab 09: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
printf 'ALL CHECKS PASSED\n'
