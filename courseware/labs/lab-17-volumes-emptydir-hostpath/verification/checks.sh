#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Lab 17 — Volumes: emptyDir, hostPath and the Container Filesystem
# Graded verification. READ-ONLY: this script never creates, mutates or
# deletes a cluster object. Every query is scoped to the lab namespace.
#
#   usage:  bash verification/checks.sh
#   env:    KUBECTL=/path/to/kubectl   (default: kubectl)
#           NS=kcna-lab17              (default: kcna-lab17)
# ---------------------------------------------------------------------------
set -uo pipefail

KUBECTL="${KUBECTL:-kubectl}"
NS="${NS:-kcna-lab17}"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0

pass() { printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }
check() { if [ "$1" = "0" ]; then pass "$2"; else fail "$2"; fi; }

printf '== Lab 17 verification — namespace %s ==\n' "$NS"

if ! command -v "$KUBECTL" >/dev/null 2>&1; then
  printf '[FAIL] kubectl not found on PATH (set KUBECTL=/path/to/kubectl)\n'
  exit 2
fi

if ! "$KUBECTL" get namespace "$NS" >/dev/null 2>&1; then
  fail "namespace $NS exists"
  printf -- '------------------------------------------------\n'
  printf '%d passed, %d failed\n' "$PASS" "$FAIL"
  printf 'Run the lab from Step 1 before running these checks.\n'
  exit 1
fi
pass "namespace $NS exists"

# --- 1. seed dataset reached the cluster -----------------------------------
SEED_LINES="$("$KUBECTL" -n "$NS" get configmap tracklane-seed \
  -o jsonpath='{.data.shipments\.csv}' 2>/dev/null | grep -c '' || true)"
EXPECTED_LINES="$(grep -c '' "$LAB_DIR/data/shipments.csv" 2>/dev/null || echo 0)"
if [ -n "$SEED_LINES" ] && [ "$SEED_LINES" = "$EXPECTED_LINES" ] && [ "$SEED_LINES" != "0" ]; then
  pass "configmap tracklane-seed carries $SEED_LINES lines of seed data"
else
  fail "configmap tracklane-seed should carry $EXPECTED_LINES lines (saw '${SEED_LINES:-none}')"
fi

# --- 2. the shared-emptyDir Pod is healthy ---------------------------------
PHASE="$("$KUBECTL" -n "$NS" get pod lane-report -o jsonpath='{.status.phase}' 2>/dev/null || true)"
READY_COUNT="$("$KUBECTL" -n "$NS" get pod lane-report \
  -o jsonpath='{range .status.containerStatuses[*]}{.ready}{"\n"}{end}' 2>/dev/null \
  | grep -c '^true$' || true)"
if [ "$PHASE" = "Running" ] && [ "${READY_COUNT:-0}" = "2" ]; then
  pass "pod/lane-report is Running with 2/2 containers ready"
else
  fail "pod/lane-report should be Running with 2/2 ready (phase='${PHASE:-absent}', ready=${READY_COUNT:-0})"
fi

# --- 3. the volume really is an emptyDir -----------------------------------
"$KUBECTL" -n "$NS" get pod lane-report \
  -o jsonpath='{.spec.volumes[?(@.name=="report")].emptyDir.sizeLimit}' 2>/dev/null \
  | grep -q '64Mi'
check $? "emptyDir volume 'report' is declared on pod/lane-report"

BUILDER_MOUNT="$("$KUBECTL" -n "$NS" get pod lane-report \
  -o jsonpath='{.spec.containers[?(@.name=="report-builder")].volumeMounts[?(@.name=="report")].mountPath}' 2>/dev/null || true)"
WEB_MOUNT="$("$KUBECTL" -n "$NS" get pod lane-report \
  -o jsonpath='{.spec.containers[?(@.name=="report-web")].volumeMounts[?(@.name=="report")].mountPath}' 2>/dev/null || true)"
if [ "$BUILDER_MOUNT" = "/shared" ] && [ "$WEB_MOUNT" = "/shared" ]; then
  pass "report-builder and report-web both mount the 'report' volume"
else
  fail "both containers must mount volume 'report' at /shared (builder='$BUILDER_MOUNT', web='$WEB_MOUNT')"
fi

# --- 4. the dataset was genuinely consumed ---------------------------------
DATA_ROWS=$(( EXPECTED_LINES - 1 ))
"$KUBECTL" -n "$NS" exec lane-report -c report-web -- cat /shared/index.html 2>/dev/null \
  | grep -q "rows: ${DATA_ROWS}<"
check $? "/shared/index.html reports ${DATA_ROWS} rows (matches data/shipments.csv)"

# --- 5. cross-container sharing is real ------------------------------------
"$KUBECTL" -n "$NS" exec lane-report -c report-web -- test -s /shared/index.html 2>/dev/null
check $? "report-web sees the file written by report-builder (cross-container share)"

# --- 6. memory-backed emptyDir ---------------------------------------------
MEDIUM="$("$KUBECTL" -n "$NS" get pod lane-cache \
  -o jsonpath='{.spec.volumes[?(@.name=="cache")].emptyDir.medium}' 2>/dev/null || true)"
LIMIT="$("$KUBECTL" -n "$NS" get pod lane-cache \
  -o jsonpath='{.spec.volumes[?(@.name=="cache")].emptyDir.sizeLimit}' 2>/dev/null || true)"
if [ "$MEDIUM" = "Memory" ] && [ "$LIMIT" = "32Mi" ]; then
  pass "pod/lane-cache mounts a Memory-medium emptyDir with sizeLimit 32Mi"
else
  fail "pod/lane-cache needs emptyDir.medium=Memory sizeLimit=32Mi (saw '$MEDIUM'/'$LIMIT')"
fi

"$KUBECTL" -n "$NS" exec lane-cache -- df -h /cache 2>/dev/null | grep -q 'tmpfs'
check $? "/cache is a tmpfs sized 32.0M"

# --- 7. hostPath is mounted with an assertion and read-only ----------------
HP_PATH="$("$KUBECTL" -n "$NS" get pod node-log-peek \
  -o jsonpath='{.spec.volumes[?(@.name=="node-logs")].hostPath.path}' 2>/dev/null || true)"
HP_TYPE="$("$KUBECTL" -n "$NS" get pod node-log-peek \
  -o jsonpath='{.spec.volumes[?(@.name=="node-logs")].hostPath.type}' 2>/dev/null || true)"
if [ "$HP_PATH" = "/var/log" ] && [ "$HP_TYPE" = "Directory" ]; then
  pass "pod/node-log-peek mounts hostPath /var/log with type Directory"
else
  fail "hostPath should be /var/log with type Directory (saw '$HP_PATH'/'$HP_TYPE')"
fi

"$KUBECTL" -n "$NS" get pod node-log-peek \
  -o jsonpath='{.spec.containers[0].volumeMounts[?(@.name=="node-logs")].readOnly}' 2>/dev/null \
  | grep -q 'true'
check $? "the hostPath mount is readOnly"

# --- 8. safety gate: nothing in this namespace is privileged ---------------
PRIV="$("$KUBECTL" -n "$NS" get pods \
  -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.securityContext.privileged}{"\n"}{end}{end}' 2>/dev/null \
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
