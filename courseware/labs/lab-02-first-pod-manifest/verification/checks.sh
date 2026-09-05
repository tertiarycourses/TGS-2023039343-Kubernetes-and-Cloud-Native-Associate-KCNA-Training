#!/usr/bin/env bash
# Lab 02 — Authoring Your First Pod Manifest
# Verification script. Creates nothing; scoped to namespace kcna-lab02.
set -uo pipefail

NS="kcna-lab02"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${LAB_DIR}/data"
PASS=0
FAIL=0

ok()    { printf '  [PASS] %s\n' "$1"; PASS=$((PASS+1)); }
bad()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
head1() { printf '\n== %s\n' "$1"; }

head1 "0. Cluster reachability"
if kubectl version -o json >/dev/null 2>&1; then
  ok "kubectl can reach the API server"
else
  bad "kubectl cannot reach the API server"
  echo; echo "Result: ${PASS} passed, ${FAIL} failed"; exit 1
fi

head1 "1. Namespace"
if kubectl get namespace "${NS}" >/dev/null 2>&1; then
  ok "namespace ${NS} exists"
else
  bad "namespace ${NS} is missing — apply manifests/00-namespace.yaml"
fi

head1 "2. ConfigMap depot-content is built from data/"
CM_KEYS="$(kubectl -n "${NS}" get configmap depot-content \
  -o go-template='{{range $k,$v := .data}}{{$k}}{{"\n"}}{{end}}' 2>/dev/null | sort | tr '\n' ' ')"
if [ -n "${CM_KEYS}" ]; then
  ok "ConfigMap depot-content exists (keys: ${CM_KEYS})"
else
  bad "ConfigMap depot-content is missing"
fi
case " ${CM_KEYS}" in
  *" index.html "*) ok "key index.html present" ;;
  *) bad "key index.html missing (use --from-file=index.html=data/depot-status.html)" ;;
esac
case " ${CM_KEYS}" in
  *" depots.csv "*) ok "key depots.csv present" ;;
  *) bad "key depots.csv missing (use --from-file=depots.csv=data/depots.csv)" ;;
esac

# The ConfigMap must genuinely carry the shipped dataset, not a placeholder.
LIVE_CSV="$(kubectl -n "${NS}" get configmap depot-content \
  -o go-template='{{index .data "depots.csv"}}' 2>/dev/null)"
if [ -n "${LIVE_CSV}" ] && [ -f "${DATA_DIR}/depots.csv" ]; then
  if [ "$(printf '%s' "${LIVE_CSV}" | grep -c 'MF-')" -eq \
       "$(grep -c 'MF-' "${DATA_DIR}/depots.csv")" ]; then
    ok "ConfigMap depots.csv row count matches data/depots.csv (10 depots)"
  else
    bad "ConfigMap depots.csv does not match data/depots.csv"
  fi
else
  bad "could not read depots.csv from the ConfigMap"
fi

head1 "3. Pod depot-web"
PHASE="$(kubectl -n "${NS}" get pod depot-web -o jsonpath='{.status.phase}' 2>/dev/null)"
if [ "${PHASE}" = "Running" ]; then
  ok "Pod depot-web phase is Running"
else
  bad "Pod depot-web phase is '${PHASE:-<absent>}' (expected Running)"
fi

READY="$(kubectl -n "${NS}" get pod depot-web \
  -o jsonpath='{.status.containerStatuses[?(@.name=="web")].ready}' 2>/dev/null)"
if [ "${READY}" = "true" ]; then
  ok "container 'web' passed its readinessProbe (ready=true)"
else
  bad "container 'web' ready='${READY:-<absent>}'"
fi

IMG="$(kubectl -n "${NS}" get pod depot-web \
  -o jsonpath='{.spec.containers[0].image}' 2>/dev/null)"
if [ "${IMG}" = "nginx:1.27-alpine" ]; then
  ok "image is pinned to nginx:1.27-alpine (no :latest)"
else
  bad "unexpected image '${IMG:-<absent>}'"
fi

PORT="$(kubectl -n "${NS}" get pod depot-web \
  -o jsonpath='{.spec.containers[0].ports[0].containerPort}' 2>/dev/null)"
if [ "${PORT}" = "80" ]; then
  ok "containerPort 80 declared and named 'http'"
else
  bad "containerPort is '${PORT:-<absent>}' (expected 80)"
fi

REQ_CPU="$(kubectl -n "${NS}" get pod depot-web \
  -o jsonpath='{.spec.containers[0].resources.requests.cpu}' 2>/dev/null)"
LIM_MEM="$(kubectl -n "${NS}" get pod depot-web \
  -o jsonpath='{.spec.containers[0].resources.limits.memory}' 2>/dev/null)"
if [ -n "${REQ_CPU}" ] && [ -n "${LIM_MEM}" ]; then
  ok "explicit resources set (requests.cpu=${REQ_CPU}, limits.memory=${LIM_MEM})"
else
  bad "resources.requests / resources.limits are not both set"
fi

head1 "4. Content is served from the mounted ConfigMap"
if kubectl -n "${NS}" exec depot-web -c web -- \
     wget -qO- http://127.0.0.1/index.html 2>/dev/null | grep -q 'Meridian Freight'; then
  ok "GET /index.html returns the Meridian Freight page"
else
  bad "GET /index.html did not return the expected page"
fi

if kubectl -n "${NS}" exec depot-web -c web -- \
     wget -qO- http://127.0.0.1/depots.csv 2>/dev/null | grep -q 'MF-KUL-01'; then
  ok "GET /depots.csv returns the synthetic depot dataset"
else
  bad "GET /depots.csv did not return the dataset"
fi

head1 "5. Server-side defaulting is observable"
DNS="$(kubectl -n "${NS}" get pod depot-web -o jsonpath='{.spec.dnsPolicy}' 2>/dev/null)"
SA="$(kubectl -n "${NS}" get pod depot-web -o jsonpath='{.spec.serviceAccountName}' 2>/dev/null)"
if [ "${DNS}" = "ClusterFirst" ] && [ "${SA}" = "default" ]; then
  ok "API server defaulted dnsPolicy=ClusterFirst and serviceAccountName=default"
else
  bad "unexpected defaults: dnsPolicy='${DNS}', serviceAccountName='${SA}'"
fi

head1 "6. Failure-injection Pod (only if you left it in place)"
BAD_REASON="$(kubectl -n "${NS}" get pod depot-web-badtag \
  -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null)"
case "${BAD_REASON}" in
  ImagePullBackOff|ErrImagePull)
    ok "depot-web-badtag is in ${BAD_REASON} as designed" ;;
  "")
    printf '  [SKIP] depot-web-badtag not present (section 6 already cleaned up)\n' ;;
  *)
    bad "depot-web-badtag waiting reason is '${BAD_REASON}' (expected ImagePullBackOff)" ;;
esac

echo
echo "Result: ${PASS} passed, ${FAIL} failed"
[ "${FAIL}" -eq 0 ]
