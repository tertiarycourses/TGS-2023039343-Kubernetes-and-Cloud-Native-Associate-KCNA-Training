#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Lab 25 — Troubleshooting Triage : verification
# Meridian Freight Pte Ltd · Depot Portal platform
#
# Read-only against the cluster: creates, patches and deletes nothing, and
# touches kube-system only with `get`.
#
# Run:  bash verification/checks.sh
# ---------------------------------------------------------------------------
set -uo pipefail

NS="${NS:-kcna-lab25}"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
SKIP=0

ok()    { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad()   { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
skip()  { printf '  SKIP  %s\n' "$1"; SKIP=$((SKIP + 1)); }
head2() { printf '\n== %s\n' "$1"; }

command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found on PATH"; exit 2; }

head2 "Namespace isolation"
if kubectl get namespace "$NS" >/dev/null 2>&1; then
  ok "namespace $NS exists"
else
  bad "namespace $NS does not exist — run: kubectl apply -f manifests/00-namespace.yaml"
  echo; echo "SUMMARY: $PASS passed, $FAIL failed, $SKIP skipped"; exit 1
fi

enforce=$(kubectl get namespace "$NS" \
  -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null)
if [ "$enforce" = "baseline" ]; then
  ok "Pod Security Admission enforce=baseline"
else
  bad "expected PSA enforce=baseline, got '${enforce:-<unset>}'"
fi

# -------------------------------------------------------------------------
# The broken manifests must remain SCHEMA-VALID. The breakage is semantic:
# a bad tag, a missing binary, impossible resources, a selector mismatch.
# If any of these ever became a schema violation, the learner would see the
# apply rejected instead of a runtime failure, and the lab would teach the
# wrong lesson.
# -------------------------------------------------------------------------
head2 "broken/ manifests are schema-valid (semantic breakage only)"
BROKEN_DIR="$LAB_DIR/broken"
expected_broken=4
found_broken=$(ls -1 "$BROKEN_DIR"/*.yaml 2>/dev/null | wc -l | tr -d ' ')
if [ "${found_broken:-0}" -eq "$expected_broken" ]; then
  ok "found $expected_broken broken manifests"
else
  bad "expected $expected_broken files in broken/, found ${found_broken:-0}"
fi

if command -v kubeconform >/dev/null 2>&1; then
  if kubeconform -strict -summary -kubernetes-version 1.31.0 \
       "$BROKEN_DIR"/*.yaml >/dev/null 2>&1; then
    ok "kubeconform: all broken/ manifests pass strict schema validation"
  else
    bad "kubeconform: a broken/ manifest FAILS schema validation — breakage must be semantic, not structural"
  fi
else
  skip "kubeconform not installed — skipping schema validation of broken/"
fi

# Server-side dry-run is the authoritative test: it proves the API server
# would accept these objects. No object is created.
if kubectl apply --dry-run=server -f "$BROKEN_DIR"/ >/dev/null 2>&1; then
  ok "server-side dry-run: the API server ACCEPTS all broken/ manifests"
else
  bad "server-side dry-run rejected a broken/ manifest — it must fail at RUNTIME, not at admission"
fi

head2 "Part 1 — known-good baseline"
if kubectl get deployment depot-portal -n "$NS" >/dev/null 2>&1; then
  ok "deployment/depot-portal (reference workload) exists"
  ready=$(kubectl get deployment depot-portal -n "$NS" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  if [ "${ready:-0}" -ge 1 ] 2>/dev/null; then
    ok "reference workload has $ready ready replica(s)"
  else
    bad "reference workload has no ready replicas"
  fi
else
  bad "deployment/depot-portal missing — see Step 1.2"
fi

head2 "Part 7 — all four tickets repaired"
# Q1-Q4: every Pod in the namespace should be Running and fully Ready.
notready=$(kubectl get pods -n "$NS" \
  --no-headers 2>/dev/null | awk '$3 != "Running" && $3 != "Completed" {print $1}')
if [ -z "$notready" ]; then
  ok "every Pod in $NS is Running"
else
  bad "Pods not Running: $(echo "$notready" | tr '\n' ' ')"
fi

for d in depot-api shipment-worker manifest-indexer depot-tracker; do
  if kubectl get deployment "$d" -n "$NS" >/dev/null 2>&1; then
    want=$(kubectl get deployment "$d" -n "$NS" -o jsonpath='{.spec.replicas}')
    got=$(kubectl get deployment "$d" -n "$NS" -o jsonpath='{.status.readyReplicas}')
    got="${got:-0}"
    if [ "$got" = "$want" ]; then
      ok "$d: $got/$want ready"
    else
      bad "$d: only $got/$want ready — ticket not yet repaired"
    fi
  else
    bad "deployment/$d missing — apply broken/ then manifests/20-fixes.yaml"
  fi
done

# DEP-1041: image tag must be corrected.
img=$(kubectl get deployment depot-api -n "$NS" \
  -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
if [ "$img" = "nginx:1.27-alpine" ]; then
  ok "DEP-1041 fixed: image is $img"
else
  bad "DEP-1041 not fixed: image is '${img:-<unset>}' (expected nginx:1.27-alpine)"
fi

# DEP-1042: no restarts, and the worker is producing output.
wrestarts=$(kubectl get pods -n "$NS" -l app=shipment-worker \
  -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>/dev/null)
wrestarts="${wrestarts:-0}"
if [ "$wrestarts" -eq 0 ] 2>/dev/null; then
  ok "DEP-1042 fixed: shipment-worker has 0 restarts"
else
  bad "DEP-1042: shipment-worker restart count is $wrestarts — still crash-looping?"
fi

# DEP-1043: the Pod must actually be bound to a node.
node=$(kubectl get pods -n "$NS" -l app=manifest-indexer \
  -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)
if [ -n "$node" ]; then
  ok "DEP-1043 fixed: manifest-indexer scheduled onto $node"
else
  bad "DEP-1043 not fixed: manifest-indexer is still unscheduled (Pending)"
fi

# DEP-1044: selector must match, and endpoints must exist.
sel=$(kubectl get svc depot-tracker -n "$NS" \
  -o jsonpath='{.spec.selector.app}' 2>/dev/null)
if [ "$sel" = "depot-tracker" ]; then
  ok "DEP-1044 fixed: Service selector is app=$sel"
else
  bad "DEP-1044 not fixed: Service selector is app='${sel:-<unset>}' (expected depot-tracker)"
fi

epcount=$(kubectl get endpointslices -n "$NS" \
  -l kubernetes.io/service-name=depot-tracker \
  -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{"\n"}{end}' 2>/dev/null \
  | grep -c . || true)
if [ "${epcount:-0}" -ge 1 ]; then
  ok "DEP-1044 verified: EndpointSlice carries $epcount backend address(es)"
else
  bad "DEP-1044: EndpointSlice still has no addresses"
fi

head2 "Worksheets"
for f in incident-queue.csv triage-worksheet.csv; do
  if [ -f "$LAB_DIR/data/$f" ]; then
    ok "data/$f present"
  else
    bad "data/$f missing"
  fi
done
if head -1 "$LAB_DIR/data/triage-worksheet.csv" 2>/dev/null \
     | grep -q 'first_failing_question'; then
  ok "triage worksheet header intact"
else
  bad "triage worksheet header has been altered"
fi
for t in DEP-1041 DEP-1042 DEP-1043 DEP-1044; do
  if grep -q "^$t," "$LAB_DIR/data/triage-worksheet.csv" 2>/dev/null; then
    ok "worksheet has a row for $t"
  else
    bad "worksheet row for $t is missing"
  fi
done

head2 "Blast-radius guard — kube-system untouched"
if kubectl get deploy,po,svc,cm -n kube-system \
     -l kcna.tertiaryinfotech.com/lab=lab-25 2>/dev/null | grep -q .; then
  bad "this lab created objects in kube-system — Part 6 must be read-only"
else
  ok "no lab-25 objects in kube-system (Part 6 was read-only)"
fi

cp_ready=$(kubectl get --raw='/readyz' 2>/dev/null)
if [ "$cp_ready" = "ok" ]; then
  ok "control plane still reports readyz=ok"
else
  bad "control plane readyz is '${cp_ready:-unreachable}' — investigate before continuing"
fi

printf '\nSUMMARY: %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
