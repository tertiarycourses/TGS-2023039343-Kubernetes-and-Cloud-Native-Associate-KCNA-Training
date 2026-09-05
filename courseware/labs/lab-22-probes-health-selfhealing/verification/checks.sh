#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Lab 22 — Probes, Health and Self-Healing : verification
# Meridian Freight Pte Ltd · Depot Portal platform
#
# Read-only. This script never creates, patches or deletes anything.
# Run:  bash verification/checks.sh
# Override the namespace with:  NS=my-ns bash verification/checks.sh
# ---------------------------------------------------------------------------
set -uo pipefail

NS="${NS:-kcna-lab22}"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
head2() { printf '\n== %s\n' "$1"; }

command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found on PATH"; exit 2; }

head2 "Namespace isolation"
if kubectl get namespace "$NS" >/dev/null 2>&1; then
  ok "namespace $NS exists"
else
  bad "namespace $NS does not exist — run: kubectl apply -f manifests/00-namespace.yaml"
  echo; echo "SUMMARY: $PASS passed, $FAIL failed"; exit 1
fi

enforce=$(kubectl get namespace "$NS" \
  -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null)
if [ "$enforce" = "baseline" ]; then
  ok "Pod Security Admission enforce=baseline"
else
  bad "expected PSA enforce=baseline, got '${enforce:-<unset>}'"
fi

head2 "Part 1 — content ConfigMap sourced from data/"
if kubectl get configmap depot-portal-content -n "$NS" >/dev/null 2>&1; then
  ok "configmap/depot-portal-content exists"
  for key in index.html ready.html; do
    content="$(kubectl get configmap depot-portal-content -n "$NS" \
      -o "go-template={{index .data \"$key\"}}" 2>/dev/null)"
    if [ -n "$content" ] && [ "$content" != '<no value>' ]; then
      ok "configmap key '$key' is populated"
    else
      bad "configmap key '$key' is missing or empty"
    fi
  done
else
  bad "configmap/depot-portal-content missing — see Step 1.3"
fi

head2 "Part 2 — depot-portal probes"
if kubectl get deployment depot-portal -n "$NS" >/dev/null 2>&1; then
  ok "deployment/depot-portal exists"

  rpath=$(kubectl get deployment depot-portal -n "$NS" \
    -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}')
  lpath=$(kubectl get deployment depot-portal -n "$NS" \
    -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet.path}')

  [ -n "$rpath" ] && ok "readinessProbe configured (path=$rpath)" \
                  || bad "readinessProbe missing on container 0"
  [ -n "$lpath" ] && ok "livenessProbe configured (path=$lpath)" \
                  || bad "livenessProbe missing on container 0"

  if [ -n "$rpath" ] && [ -n "$lpath" ] && [ "$rpath" != "$lpath" ]; then
    ok "readiness and liveness target DIFFERENT paths ($rpath vs $lpath)"
  else
    bad "readiness and liveness should target different paths so their effects can be separated"
  fi

  img=$(kubectl get deployment depot-portal -n "$NS" \
    -o jsonpath='{.spec.template.spec.containers[0].image}')
  case "$img" in
    *:latest|"") bad "container image must be pinned, got '${img:-<unset>}'" ;;
    *:*)         ok "container image is pinned ($img)" ;;
    *)           bad "container image has no tag ('$img')" ;;
  esac

  ready=$(kubectl get deployment depot-portal -n "$NS" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  ready="${ready:-0}"
  if [ "$ready" -ge 1 ] 2>/dev/null; then
    ok "depot-portal has $ready ready replica(s)"
  else
    bad "depot-portal has no ready replicas yet — wait, then re-run"
  fi
else
  bad "deployment/depot-portal missing — see Step 2.2"
fi

head2 "Part 3 — Service backends via EndpointSlice"
if kubectl get service depot-portal -n "$NS" >/dev/null 2>&1; then
  ok "service/depot-portal exists"
  count=$(kubectl get endpointslices -n "$NS" \
    -l kubernetes.io/service-name=depot-portal \
    -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{"\n"}{end}' 2>/dev/null \
    | grep -c . || true)
  if [ "${count:-0}" -ge 1 ]; then
    ok "EndpointSlice carries $count backend address(es)"
  else
    bad "EndpointSlice has no backend addresses — check the Service selector and Pod readiness"
  fi
else
  bad "service/depot-portal missing — see Step 2.2"
fi

head2 "Part 4 — manifest-indexer startup probe"
if kubectl get deployment manifest-indexer -n "$NS" >/dev/null 2>&1; then
  ok "deployment/manifest-indexer exists"

  sft=$(kubectl get deployment manifest-indexer -n "$NS" \
    -o jsonpath='{.spec.template.spec.containers[0].startupProbe.failureThreshold}')
  sps=$(kubectl get deployment manifest-indexer -n "$NS" \
    -o jsonpath='{.spec.template.spec.containers[0].startupProbe.periodSeconds}')

  if [ -n "$sft" ] && [ -n "$sps" ]; then
    budget=$((sft * sps))
    ok "startupProbe present (failureThreshold=$sft x periodSeconds=${sps}s = ${budget}s budget)"
    if [ "$budget" -gt 40 ]; then
      ok "startup budget ${budget}s exceeds the app's ~40s boot time"
    else
      bad "startup budget ${budget}s does NOT exceed the ~40s boot time — restart loop expected"
    fi
  else
    bad "startupProbe missing on manifest-indexer — see Step 4.1"
  fi

  restarts=$(kubectl get pods -n "$NS" -l app=manifest-indexer \
    -o jsonpath='{.items[*].status.containerStatuses[0].restartCount}' 2>/dev/null)
  restarts="${restarts:-0}"
  if [ "${restarts// /}" = "0" ]; then
    ok "manifest-indexer reached Ready with 0 restarts"
  else
    bad "manifest-indexer restart count is '$restarts' — the startup budget is too small"
  fi
else
  bad "deployment/manifest-indexer missing — see Step 4.1"
fi

head2 "Part 6 — failure injection cleaned up"
if kubectl get deployment manifest-indexer-outage -n "$NS" >/dev/null 2>&1; then
  bad "manifest-indexer-outage still present — see Step 6.10"
else
  ok "injected deployment manifest-indexer-outage removed"
fi

head2 "Worksheet"
WS="$LAB_DIR/data/probe-tuning-worksheet.csv"
if [ -f "$WS" ]; then
  ok "worksheet present at data/probe-tuning-worksheet.csv"
  if head -1 "$WS" | grep -q 'observed_time_to_first_success_s'; then
    ok "worksheet header intact"
  else
    bad "worksheet header has been altered"
  fi
else
  bad "worksheet missing at $WS"
fi

head2 "Blast-radius guard"
if kubectl get deploy,po,svc -n kube-system \
     -l kcna.tertiaryinfotech.com/lab=lab-22 2>/dev/null | grep -q .; then
  bad "this lab created objects in kube-system — it must not"
else
  ok "no lab-22 objects in kube-system"
fi

printf '\nSUMMARY: %d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
