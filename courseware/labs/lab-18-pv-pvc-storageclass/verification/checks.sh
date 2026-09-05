#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Lab 18 — PersistentVolumes, Claims and StorageClasses
# Graded verification. READ-ONLY: never creates, mutates or deletes anything.
#
# Run AFTER Step 12, with pod/archive-auditor and deployment/render-cache up.
#
#   usage:  bash verification/checks.sh
#   env:    KUBECTL=/path/to/kubectl   (default: kubectl)
#           NS=kcna-lab18              (default: kcna-lab18)
# ---------------------------------------------------------------------------
set -uo pipefail

KUBECTL="${KUBECTL:-kubectl}"
NS="${NS:-kcna-lab18}"
PV_NAME="tracklane-archive-pv"
SC_NAME="tracklane-retain"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0
pass() { printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }
check() { if [ "$1" = "0" ]; then pass "$2"; else fail "$2"; fi; }
jp() { "$KUBECTL" "$@" 2>/dev/null || true; }

printf '== Lab 18 verification — namespace %s ==\n' "$NS"

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

# --- 1. the static PersistentVolume ----------------------------------------
if "$KUBECTL" get pv "$PV_NAME" >/dev/null 2>&1; then
  PV_NS="$(jp get pv "$PV_NAME" -o jsonpath='{.metadata.namespace}')"
  if [ -z "$PV_NS" ]; then
    pass "PersistentVolume $PV_NAME exists and is cluster-scoped"
  else
    fail "PersistentVolume $PV_NAME unexpectedly reports namespace '$PV_NS'"
  fi
else
  fail "PersistentVolume $PV_NAME exists and is cluster-scoped"
fi

PV_CAP="$(jp get pv "$PV_NAME" -o jsonpath='{.spec.capacity.storage}')"
PV_AM="$(jp get pv "$PV_NAME" -o jsonpath='{.spec.accessModes[0]}')"
PV_RP="$(jp get pv "$PV_NAME" -o jsonpath='{.spec.persistentVolumeReclaimPolicy}')"
if [ "$PV_CAP" = "1Gi" ] && [ "$PV_AM" = "ReadWriteOnce" ] && [ "$PV_RP" = "Retain" ]; then
  pass "$PV_NAME capacity=1Gi accessMode=ReadWriteOnce reclaim=Retain"
else
  fail "$PV_NAME should be 1Gi/ReadWriteOnce/Retain (saw '$PV_CAP'/'$PV_AM'/'$PV_RP')"
fi

CR_NS="$(jp get pv "$PV_NAME" -o jsonpath='{.spec.claimRef.namespace}')"
CR_NAME="$(jp get pv "$PV_NAME" -o jsonpath='{.spec.claimRef.name}')"
if [ "$CR_NS" = "$NS" ] && [ "$CR_NAME" = "archive-claim" ]; then
  pass "$PV_NAME is pre-bound via claimRef to $NS/archive-claim"
else
  fail "$PV_NAME claimRef should be $NS/archive-claim (saw '$CR_NS/$CR_NAME')"
fi

# --- 2. static binding ------------------------------------------------------
PVC_PHASE="$(jp -n "$NS" get pvc archive-claim -o jsonpath='{.status.phase}')"
PVC_VOL="$(jp -n "$NS" get pvc archive-claim -o jsonpath='{.spec.volumeName}')"
if [ "$PVC_PHASE" = "Bound" ] && [ "$PVC_VOL" = "$PV_NAME" ]; then
  pass "pvc/archive-claim is Bound to $PV_NAME"
else
  fail "pvc/archive-claim should be Bound to $PV_NAME (saw '$PVC_PHASE'/'$PVC_VOL')"
fi

REQ="$(jp -n "$NS" get pvc archive-claim -o jsonpath='{.spec.resources.requests.storage}')"
GOT="$(jp -n "$NS" get pvc archive-claim -o jsonpath='{.status.capacity.storage}')"
if [ "$REQ" = "512Mi" ] && [ "$GOT" = "1Gi" ]; then
  pass "archive-claim requested 512Mi but was granted the PV's full 1Gi"
else
  fail "expected request=512Mi granted=1Gi (saw '$REQ'/'$GOT')"
fi

# --- 3. the dataset genuinely reached the volume ---------------------------
EXPECTED_ROWS=$(( $(grep -c '' "$LAB_DIR/data/manifest-archive.csv" 2>/dev/null || echo 1) - 1 ))
"$KUBECTL" -n "$NS" exec archive-auditor -- \
  sh -c "test \$(( \$(wc -l < /archive/manifest-archive.csv) - 1 )) -eq ${EXPECTED_ROWS}" \
  >/dev/null 2>&1
check $? "the archive on the PV holds ${EXPECTED_ROWS} rows (matches data/manifest-archive.csv)"

SEEDER_GONE=1
if "$KUBECTL" -n "$NS" get pod archive-seeder >/dev/null 2>&1; then SEEDER_GONE=0; fi
PROV="$(jp -n "$NS" exec archive-auditor -- cat /archive/PROVENANCE | grep '^sealed_by=')"
if [ "$SEEDER_GONE" = "1" ] && [ "$PROV" = "sealed_by=archive-seeder" ]; then
  pass "PROVENANCE on the PV was written by a Pod that no longer exists"
else
  fail "expected PROVENANCE sealed_by=archive-seeder with the seeder Pod deleted (saw '$PROV')"
fi

# --- 4. the second StorageClass --------------------------------------------
SC_RP="$(jp get storageclass "$SC_NAME" -o jsonpath='{.reclaimPolicy}')"
if [ "$SC_RP" = "Retain" ]; then
  pass "storageclass $SC_NAME exists with reclaimPolicy=Retain"
else
  fail "storageclass $SC_NAME should have reclaimPolicy=Retain (saw '$SC_RP')"
fi

SC_BM="$(jp get storageclass "$SC_NAME" -o jsonpath='{.volumeBindingMode}')"
if [ "$SC_BM" = "WaitForFirstConsumer" ]; then
  pass "$SC_NAME uses volumeBindingMode=WaitForFirstConsumer"
else
  fail "$SC_NAME should use WaitForFirstConsumer (saw '$SC_BM')"
fi

# --- 5. dynamic provisioning ------------------------------------------------
DYN_PHASE="$(jp -n "$NS" get pvc render-cache -o jsonpath='{.status.phase}')"
DYN_VOL="$(jp -n "$NS" get pvc render-cache -o jsonpath='{.spec.volumeName}')"
case "$DYN_VOL" in
  pvc-*) DYN_OK=0 ;;
  *)     DYN_OK=1 ;;
esac
if [ "$DYN_PHASE" = "Bound" ] && [ "$DYN_OK" = "0" ]; then
  pass "pvc/render-cache is Bound to a dynamically provisioned pvc-* volume"
else
  fail "pvc/render-cache should be Bound to a pvc-* volume (saw '$DYN_PHASE'/'$DYN_VOL')"
fi

if [ -n "$DYN_VOL" ]; then
  DYN_RP="$(jp get pv "$DYN_VOL" -o jsonpath='{.spec.persistentVolumeReclaimPolicy}')"
else
  DYN_RP=""
fi
if [ "$DYN_RP" = "Delete" ]; then
  pass "the dynamic PV inherited reclaimPolicy=Delete from storageclass standard"
else
  fail "the dynamic PV should have reclaimPolicy=Delete (saw '$DYN_RP')"
fi

AVAIL="$(jp -n "$NS" get deployment render-cache -o jsonpath='{.status.availableReplicas}')"
MOUNTED="$(jp -n "$NS" get deployment render-cache \
  -o jsonpath='{.spec.template.spec.volumes[?(@.name=="cache")].persistentVolumeClaim.claimName}')"
if [ "${AVAIL:-0}" -ge 1 ] 2>/dev/null && [ "$MOUNTED" = "render-cache" ]; then
  pass "deployment/render-cache is available and mounts pvc/render-cache"
else
  fail "deployment/render-cache should be available and mount pvc/render-cache (avail='${AVAIL:-0}', claim='$MOUNTED')"
fi

STARTS="$(jp -n "$NS" exec deployment/render-cache -- grep -c '^start ' /cache/starts.log)"
if [ -n "$STARTS" ] && [ "$STARTS" -ge 2 ] 2>/dev/null; then
  pass "/cache/starts.log survived a rollout restart (${STARTS} start records)"
else
  fail "/cache/starts.log should hold 2+ start records after the rollout restart (saw '${STARTS:-0}')"
fi

printf -- '------------------------------------------------\n'
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
