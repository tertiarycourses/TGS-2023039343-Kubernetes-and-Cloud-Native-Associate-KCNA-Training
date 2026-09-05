#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Lab 23 — Events, Logs, Field Selectors and the Metrics Server : verification
# Meridian Freight Pte Ltd · Depot Portal platform
#
# Read-only. This script never creates, patches or deletes anything.
# It AUTO-DETECTS whether you installed metrics-server (Part 5 Path A) or
# skipped it (Path B). Path B is a valid completion; metrics checks are then
# reported as SKIP, not FAIL.
#
# Run:  bash verification/checks.sh
# ---------------------------------------------------------------------------
set -uo pipefail

NS="${NS:-kcna-lab23}"
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

head2 "Part 1 — access-log corpus loaded from data/"
if kubectl get configmap depot-access-log -n "$NS" >/dev/null 2>&1; then
  ok "configmap/depot-access-log exists"
  corpus="$(kubectl get configmap depot-access-log -n "$NS" \
    -o "go-template={{index .data \"depot-portal-access.log\"}}" 2>/dev/null)"
  if [ -n "$corpus" ] && [ "$corpus" != '<no value>' ]; then
    lines=$(printf '%s\n' "$corpus" | grep -c . || true)
    ok "corpus loaded ($lines lines)"
    if printf '%s\n' "$corpus" | grep -q 'upstream_timeout'; then
      ok "corpus contains the ERROR/upstream_timeout records used in Part 4"
    else
      bad "corpus does not look like the supplied data/depot-portal-access.log"
    fi
  else
    bad "configmap key 'depot-portal-access.log' is missing or empty"
  fi
else
  bad "configmap/depot-access-log missing — see Step 1.2"
fi

head2 "Part 2 — event-producing workloads"
for d in depot-portal gate-scanner; do
  if kubectl get deployment "$d" -n "$NS" >/dev/null 2>&1; then
    ok "deployment/$d exists"
  else
    bad "deployment/$d missing — see Step 2.1"
  fi
done

if kubectl get pod depot-gate-agent -n "$NS" >/dev/null 2>&1; then
  ok "pod/depot-gate-agent exists (the FailedMount event source)"
else
  bad "pod/depot-gate-agent missing — see Step 2.1"
fi

ccount=$(kubectl get deployment depot-portal -n "$NS" \
  -o jsonpath='{.spec.template.spec.containers[*].name}' 2>/dev/null | wc -w | tr -d ' ')
if [ "${ccount:-0}" -eq 2 ]; then
  ok "depot-portal Pod has 2 containers (portal + audit-sidecar)"
else
  bad "expected 2 containers on depot-portal, found ${ccount:-0}"
fi

head2 "Part 3 — Events and field selectors"
warncount=$(kubectl get events -n "$NS" \
  --field-selector involvedObject.kind=Pod,type=Warning \
  --no-headers 2>/dev/null | grep -c . || true)
if [ "${warncount:-0}" -ge 1 ]; then
  ok "compound field selector returns $warncount Warning event(s) about Pods"
else
  bad "no Warning events yet — wait ~60s after Step 2.1, then re-run"
fi

if kubectl get events -n "$NS" --field-selector reason=FailedMount \
     --no-headers 2>/dev/null | grep -q .; then
  ok "reason=FailedMount selector returns the depot-gate-agent event"
else
  bad "no FailedMount event — is pod/depot-gate-agent applied?"
fi

# The unsupported-field-selector behaviour is itself a teaching point.
if kubectl get events -n "$NS" --field-selector message=x 2>&1 \
     | grep -q 'field label not supported'; then
  ok "non-indexed field selector is rejected server-side (expected)"
else
  skip "server did not reject field-selector on 'message' — note the difference"
fi

head2 "Part 4 — logs"
POD=$(kubectl get pods -n "$NS" -l app=depot-portal \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$POD" ]; then
  ok "found depot-portal pod $POD"
  if kubectl logs -n "$NS" "$POD" -c portal --tail=20 2>/dev/null \
       | grep -q 'depot-portal gate=sg-tuas'; then
    ok "container 'portal' is emitting the data/ corpus to stdout"
  else
    bad "no corpus lines on stdout of container 'portal'"
  fi
  if kubectl logs -n "$NS" "$POD" -c audit-sidecar --tail=20 2>/dev/null \
       | grep -q 'AUDIT seq='; then
    ok "container 'audit-sidecar' is shipping its file to stdout"
  else
    bad "no AUDIT records on stdout of container 'audit-sidecar'"
  fi
else
  bad "no depot-portal pod found"
fi

SCANNER=$(kubectl get pods -n "$NS" -l app=gate-scanner \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$SCANNER" ]; then
  restarts=$(kubectl get pod -n "$NS" "$SCANNER" \
    -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
  restarts="${restarts:-0}"
  if [ "$restarts" -ge 1 ] 2>/dev/null; then
    ok "gate-scanner has restarted $restarts time(s) — --previous is meaningful"
  else
    skip "gate-scanner has not restarted yet — wait ~30s for --previous to work"
  fi
else
  bad "no gate-scanner pod found"
fi

head2 "Part 5 — metrics pipeline (Path A or Path B)"
if kubectl get apiservice v1beta1.metrics.k8s.io >/dev/null 2>&1; then
  ok "APIService v1beta1.metrics.k8s.io exists (Path A)"
  avail=$(kubectl get apiservice v1beta1.metrics.k8s.io \
    -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
  if [ "$avail" = "True" ]; then
    ok "aggregation layer reports Available=True"
  else
    bad "APIService Available='${avail:-unknown}' — see the Troubleshooting table"
  fi

  args=$(kubectl get deployment metrics-server -n "$NS" \
    -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null)
  if printf '%s' "$args" | grep -q 'kubelet-insecure-tls'; then
    ok "--kubelet-insecure-tls present (required on kind; lab clusters only)"
  else
    bad "--kubelet-insecure-tls absent — metrics-server cannot scrape kind kubelets"
  fi

  img=$(kubectl get deployment metrics-server -n "$NS" \
    -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
  case "$img" in
    *:latest|"") bad "metrics-server image must be pinned, got '${img:-<unset>}'" ;;
    *:*)         ok "metrics-server image is pinned ($img)" ;;
    *)           bad "metrics-server image has no tag" ;;
  esac

  if kubectl top pods -n "$NS" >/dev/null 2>&1; then
    ok "kubectl top pods returns data"
  else
    bad "kubectl top pods still failing — allow ~60s for the first scrape window"
  fi
else
  skip "metrics.k8s.io not installed — Path B. This is a VALID completion."
  skip "kubectl top checks not applicable on Path B"
  if kubectl top pods -n "$NS" 2>&1 | grep -q 'Metrics API not available'; then
    ok "kubectl top fails with the documented Path B error (expected on stock kind)"
  else
    skip "could not confirm the expected Path B error string"
  fi
fi

head2 "Worksheet"
WS="$LAB_DIR/data/event-triage-worksheet.csv"
if [ -f "$WS" ]; then
  ok "worksheet present at data/event-triage-worksheet.csv"
  if head -1 "$WS" | grep -q 'event_reason'; then
    ok "worksheet header intact"
  else
    bad "worksheet header has been altered"
  fi
else
  bad "worksheet missing at $WS"
fi

head2 "Blast-radius guard"
# The ONLY object this lab may create in kube-system is the named RoleBinding.
extra=$(kubectl get deploy,po,svc,cm,secret -n kube-system \
  -l kcna.tertiaryinfotech.com/lab=lab-23 --no-headers 2>/dev/null | grep -c . || true)
if [ "${extra:-0}" -eq 0 ]; then
  ok "no lab-23 workloads/config in kube-system"
else
  bad "unexpected lab-23 objects in kube-system: $extra"
fi

if kubectl get rolebinding kcna-lab23-metrics-server-auth-reader \
     -n kube-system >/dev/null 2>&1; then
  ok "the one documented kube-system RoleBinding is present (Path A)"
else
  skip "no kube-system RoleBinding (Path B, or already cleaned up)"
fi

printf '\nSUMMARY: %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
