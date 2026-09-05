#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Lab 20 — Control Plane Anatomy and etcd Backup/Restore
# Graded verification.
#
# SAFETY: this script is STRICTLY READ-ONLY against the control plane.
#   * It never creates, patches, restarts or deletes a control-plane object.
#   * It never runs `snapshot restore`, `defrag`, `compact` or `move-leader`.
#   * The only etcd calls it makes are `etcdctl version` and
#     `etcdctl endpoint status`, both of which are pure reads. It deliberately
#     avoids `endpoint health`, because that commits a no-op Raft proposal.
#   * It writes no file anywhere on the node or in any container.
#
#   usage:  bash verification/checks.sh
#   env:    KUBECTL=/path/to/kubectl   (default: kubectl)
#           NS=kcna-lab20              (default: kcna-lab20)
# ---------------------------------------------------------------------------
set -uo pipefail

KUBECTL="${KUBECTL:-kubectl}"
NS="${NS:-kcna-lab20}"
LAB_LABEL="kcna.tertiaryinfotech.com/lab=20"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0
pass() { printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }
check() { if [ "$1" = "0" ]; then pass "$2"; else fail "$2"; fi; }
jp() { "$KUBECTL" "$@" 2>/dev/null || true; }

printf '== Lab 20 verification — namespace %s ==\n' "$NS"

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

NODE="$(jp get nodes -o jsonpath='{.items[0].metadata.name}')"

# --- 1. control-plane health (read-only) -----------------------------------
jp get --raw='/readyz' | grep -q '^ok$'
check $? "control plane is ready (/readyz reports ok)"

jp get --raw='/readyz?verbose' | grep -q '^\[+\]etcd ok'
check $? "apiserver reports [+]etcd ok in /readyz?verbose"

# --- 2. static pods and mirror pods ----------------------------------------
STATIC_COUNT="$(jp -n kube-system get pods \
  -o jsonpath='{range .items[?(@.metadata.annotations.kubernetes\.io/config\.source=="file")]}{.metadata.name}{"\n"}{end}' \
  | grep -c '.' || true)"
EXPECTED_STATIC="$(grep -c ',StaticPod,' "$LAB_DIR/data/control-plane-inventory.csv" 2>/dev/null || echo 0)"
if [ "${STATIC_COUNT:-0}" = "$EXPECTED_STATIC" ]; then
  pass "$STATIC_COUNT static-pod components found with config.source=file"
else
  fail "expected $EXPECTED_STATIC static-pod components (saw ${STATIC_COUNT:-0})"
fi

OWNER_KIND="$(jp -n kube-system get pod "etcd-${NODE}" \
  -o jsonpath='{.metadata.ownerReferences[0].kind}')"
if [ "$OWNER_KIND" = "Node" ]; then
  pass "mirror pod etcd-${NODE} is owned by a Node, not a controller"
else
  fail "mirror pod etcd-${NODE} should be owned by a Node (saw '${OWNER_KIND:-none}')"
fi

ETCD_ARGS="$(jp -n kube-system get pod "etcd-${NODE}" \
  -o jsonpath='{.spec.containers[0].command}')"
if printf '%s' "$ETCD_ARGS" | grep -q 'listen-client-urls.*2379' \
   && printf '%s' "$ETCD_ARGS" | grep -q 'listen-peer-urls.*2380'; then
  pass "etcd static pod exposes client port 2379 and peer port 2380"
else
  fail "etcd static pod should listen on 2379 (client) and 2380 (peer)"
fi

# --- 3. the datasets genuinely reached the cluster -------------------------
EXPECTED_ROWS=$(( $(grep -c '' "$LAB_DIR/data/control-plane-inventory.csv" 2>/dev/null || echo 1) - 1 ))
CM_ROWS="$(jp -n "$NS" get configmap control-plane-inventory \
  -o jsonpath='{.data.control-plane-inventory\.csv}' | tail -n +2 | grep -c '.' || true)"
if [ "${CM_ROWS:-0}" = "$EXPECTED_ROWS" ]; then
  pass "configmap control-plane-inventory holds $CM_ROWS data rows (matches data/)"
else
  fail "configmap control-plane-inventory should hold $EXPECTED_ROWS data rows (saw ${CM_ROWS:-0})"
fi

EXPECTED_BANNERS="$(grep -c 'DO NOT RUN' "$LAB_DIR/data/etcd-restore-runbook.md" 2>/dev/null || echo 0)"
CM_BANNERS="$(jp -n "$NS" get configmap etcd-restore-runbook \
  -o jsonpath='{.data.etcd-restore-runbook\.md}' | grep -c 'DO NOT RUN' || true)"
if [ "${CM_BANNERS:-0}" = "$EXPECTED_BANNERS" ] && [ "${CM_BANNERS:-0}" != "0" ]; then
  pass "configmap etcd-restore-runbook carries $CM_BANNERS DO-NOT-RUN banners"
else
  fail "runbook should carry $EXPECTED_BANNERS DO-NOT-RUN banners (saw ${CM_BANNERS:-0})"
fi

# --- 4. the inventory Job ---------------------------------------------------
JOB_OK="$(jp -n "$NS" get job cp-inventory \
  -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')"
JOB_LOG="$(jp -n "$NS" logs job/cp-inventory)"
if [ "$JOB_OK" = "True" ] \
   && printf '%s' "$JOB_LOG" | grep -q "static_pod_components=${EXPECTED_STATIC}"; then
  pass "job/cp-inventory completed and reported static_pod_components=${EXPECTED_STATIC}"
else
  fail "job/cp-inventory should complete and report static_pod_components=${EXPECTED_STATIC}"
fi

# --- 5. least privilege -----------------------------------------------------
SA="system:serviceaccount:${NS}:cp-inventory"
CAN_KS="$(jp auth can-i list pods --namespace=kube-system --as="$SA")"
if [ "$CAN_KS" = "no" ]; then
  pass "serviceaccount cp-inventory CANNOT list pods in kube-system"
else
  fail "serviceaccount cp-inventory must NOT be able to list pods in kube-system (saw '$CAN_KS')"
fi

CAN_NS="$(jp auth can-i list pods --namespace="$NS" --as="$SA")"
if [ "$CAN_NS" = "yes" ]; then
  pass "serviceaccount cp-inventory CAN list pods in $NS"
else
  fail "serviceaccount cp-inventory should be able to list pods in $NS (saw '$CAN_NS')"
fi

# --- 6. the blueprint deliverable ------------------------------------------
POLICY="$(jp -n "$NS" get configmap etcd-backup-policy -o jsonpath='{.data.policy\.yaml}')"
if printf '%s' "$POLICY" | grep -q 'rpo_minutes:' \
   && printf '%s' "$POLICY" | grep -q 'rto_minutes:'; then
  pass "configmap etcd-backup-policy declares rpo_minutes and rto_minutes"
else
  fail "configmap etcd-backup-policy must declare rpo_minutes and rto_minutes"
fi

# --- 7. the reader Pod really cannot act -----------------------------------
AMSAT="$(jp -n "$NS" get pod runbook-reader -o jsonpath='{.spec.automountServiceAccountToken}')"
if [ "$AMSAT" = "false" ]; then
  pass "pod/runbook-reader runs with automountServiceAccountToken=false"
else
  fail "pod/runbook-reader must set automountServiceAccountToken=false (saw '${AMSAT:-unset}')"
fi

HOSTPATHS="$(jp -n "$NS" get pod runbook-reader \
  -o jsonpath='{range .spec.volumes[*]}{.hostPath.path}{"\n"}{end}' | grep -c '.' || true)"
if [ "${HOSTPATHS:-0}" = "0" ]; then
  pass "pod/runbook-reader has no hostPath volumes"
else
  fail "pod/runbook-reader must not mount any hostPath (saw ${HOSTPATHS})"
fi

# --- 8. etcd tooling reachable (PURE READS ONLY) ---------------------------
ETCD_POD="$(jp -n kube-system get pods -l component=etcd \
  -o jsonpath='{.items[0].metadata.name}')"
if [ -n "$ETCD_POD" ]; then
  "$KUBECTL" -n kube-system exec "$ETCD_POD" -- etcdctl version >/dev/null 2>&1
  check $? "etcdctl is available inside the etcd static pod ($ETCD_POD)"

  # `endpoint status` is a read. `endpoint health` is deliberately NOT used
  # here because it commits a no-op Raft proposal.
  REV="$("$KUBECTL" -n kube-system exec "$ETCD_POD" -- etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    endpoint status -w fields 2>/dev/null | sed -n 's/^"Revision" : \([0-9]*\)$/\1/p')"
  if [ -n "$REV" ] && [ "$REV" -gt 0 ] 2>/dev/null; then
    pass "etcd endpoint status reports revision $REV over TLS (read-only)"
  else
    fail "etcd endpoint status should report a non-zero revision (saw '${REV:-none}')"
  fi
else
  fail "etcdctl is available inside the etcd static pod"
  fail "etcd endpoint status reports a non-zero revision over TLS (read-only)"
fi

# --- 9. safety gates --------------------------------------------------------
PRIV="$(jp -n "$NS" get pods \
  -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.securityContext.privileged}{"\n"}{end}{end}' \
  | grep -c '^true$' || true)"
if [ "${PRIV:-0}" = "0" ]; then
  pass "no container in $NS requests privileged: true"
else
  fail "$PRIV privileged container(s) found in $NS — this lab must not need any"
fi

STRAY=0
for KIND in clusterroles clusterrolebindings persistentvolumes storageclasses; do
  N="$(jp get "$KIND" -l "$LAB_LABEL" -o name | grep -c '.' || true)"
  STRAY=$(( STRAY + ${N:-0} ))
done
if [ "$STRAY" = "0" ]; then
  pass "no cluster-scoped object was created by this lab"
else
  fail "$STRAY cluster-scoped object(s) labelled $LAB_LABEL found — this lab must create none"
fi

printf -- '------------------------------------------------\n'
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
