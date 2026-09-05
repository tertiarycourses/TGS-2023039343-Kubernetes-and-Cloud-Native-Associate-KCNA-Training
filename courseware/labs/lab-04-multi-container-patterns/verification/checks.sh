#!/usr/bin/env bash
# Lab 04 — Multi-Container Pod Patterns
# Verification script. Creates nothing; scoped to namespace kcna-lab04.
set -uo pipefail

NS="kcna-lab04"
PASS=0
FAIL=0

ok()    { printf '  [PASS] %s\n' "$1"; PASS=$((PASS+1)); }
bad()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
skip()  { printf '  [SKIP] %s\n' "$1"; }
head1() { printf '\n== %s\n' "$1"; }

pod_ready() {
  kubectl -n "${NS}" get pod "$1" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null
}

head1 "0. Cluster reachability"
if kubectl version -o json >/dev/null 2>&1; then
  ok "kubectl can reach the API server"
else
  bad "kubectl cannot reach the API server"
  echo; echo "Result: ${PASS} passed, ${FAIL} failed"; exit 1
fi

head1 "1. Namespace and ConfigMaps built from data/"
if kubectl get namespace "${NS}" >/dev/null 2>&1; then
  ok "namespace ${NS} exists"
else
  bad "namespace ${NS} is missing"
fi
if kubectl -n "${NS}" get configmap access-seed >/dev/null 2>&1; then
  ok "ConfigMap access-seed exists (from data/access-seed.log)"
else
  bad "ConfigMap access-seed is missing"
fi
if kubectl -n "${NS}" get configmap tariff-quote >/dev/null 2>&1; then
  ok "ConfigMap tariff-quote exists (from data/tariff-quote.json)"
else
  bad "ConfigMap tariff-quote is missing"
fi

head1 "2. Backend service for the ambassador"
if [ "$(pod_ready tariff-backend)" = "True" ]; then
  ok "Pod tariff-backend is Ready"
else
  bad "Pod tariff-backend is not Ready"
fi
EPS="$(kubectl -n "${NS}" get endpointslices \
  -l kubernetes.io/service-name=tariff-backend \
  -o jsonpath='{.items[0].endpoints[0].addresses[0]}' 2>/dev/null)"
if [ -n "${EPS}" ]; then
  ok "Service tariff-backend has an EndpointSlice backend (${EPS})"
else
  bad "Service tariff-backend has no ready endpoint"
fi

head1 "3. SIDECAR — depot-sidecar"
CCOUNT="$(kubectl -n "${NS}" get pod depot-sidecar \
  -o jsonpath='{.status.containerStatuses[*].name}' 2>/dev/null | wc -w | tr -d ' ')"
if [ "${CCOUNT}" = "2" ]; then
  ok "depot-sidecar has 2 containers (app, shipper)"
else
  bad "depot-sidecar reports ${CCOUNT} containers (expected 2)"
fi
if [ "$(pod_ready depot-sidecar)" = "True" ]; then
  ok "depot-sidecar is Ready"
else
  bad "depot-sidecar is not Ready"
fi
if kubectl -n "${NS}" logs depot-sidecar -c app 2>/dev/null | grep -q 'seeded 16 historical rows'; then
  ok "app seeded 16 rows from data/access-seed.log into the shared emptyDir"
else
  bad "app did not report seeding 16 rows from the ConfigMap"
fi
if kubectl -n "${NS}" logs depot-sidecar -c shipper --tail=200 2>/dev/null \
     | grep -q '2026-09-05T08:00:01Z depot=MF-SIN-02'; then
  ok "shipper re-emitted the seeded rows it never wrote — the volume is shared"
else
  bad "shipper did not emit the seeded rows"
fi

head1 "4. ADAPTER — depot-adapter"
if [ "$(pod_ready depot-adapter)" = "True" ]; then
  ok "depot-adapter is Ready"
else
  bad "depot-adapter is not Ready"
fi
ADP="$(kubectl -n "${NS}" logs depot-adapter -c adapter --tail=40 2>/dev/null)"
if printf '%s' "${ADP}" | grep -q '# TYPE depot_http_requests_total counter'; then
  ok "adapter emits Prometheus TYPE metadata"
else
  bad "adapter output is not in Prometheus text exposition format (wait ~20s and retry)"
fi
if printf '%s' "${ADP}" | grep -q 'depot_http_requests_total{depot="MF-SIN-02",code="503"}'; then
  ok "adapter derived a 503 counter from the app's key=value log"
else
  bad "adapter did not emit the 503 series"
fi

head1 "5. AMBASSADOR — depot-ambassador"
if [ "$(pod_ready depot-ambassador)" = "True" ]; then
  ok "depot-ambassador is Ready"
else
  bad "depot-ambassador is not Ready"
fi
if kubectl -n "${NS}" logs depot-ambassador -c app --tail=30 2>/dev/null \
     | grep -q 'quote via ambassador'; then
  ok "app reached the remote service through 127.0.0.1:9000"
else
  bad "app never got a quote through the ambassador (wait ~15s and retry)"
fi
if kubectl -n "${NS}" logs depot-ambassador -c ambassador --tail=50 2>/dev/null \
     | grep -q '"GET /tariff-quote.json HTTP/1.1" 200'; then
  ok "ambassador access log shows the proxied 200"
else
  bad "ambassador access log has no successful proxied request"
fi

head1 "6. NATIVE SIDECAR — depot-native-sidecar"
SC_POLICY="$(kubectl -n "${NS}" get pod depot-native-sidecar \
  -o jsonpath='{.spec.initContainers[?(@.name=="shipper")].restartPolicy}' 2>/dev/null)"
if [ "${SC_POLICY}" = "Always" ]; then
  ok "initContainer 'shipper' declares restartPolicy: Always (native sidecar)"
else
  bad "initContainer 'shipper' restartPolicy is '${SC_POLICY:-<absent>}'"
fi
if [ "$(pod_ready depot-native-sidecar)" = "True" ]; then
  ok "depot-native-sidecar is Ready"
else
  bad "depot-native-sidecar is not Ready"
fi
SC_STATE="$(kubectl -n "${NS}" get pod depot-native-sidecar \
  -o jsonpath='{.status.initContainerStatuses[?(@.name=="shipper")].state.running.startedAt}' 2>/dev/null)"
if [ -n "${SC_STATE}" ]; then
  ok "the native sidecar is still RUNNING while the app runs (started ${SC_STATE})"
else
  bad "the native sidecar is not in a running state"
fi
if kubectl -n "${NS}" logs depot-native-sidecar -c shipper --tail=200 2>/dev/null \
     | grep -q 'native sidecar up BEFORE the app container'; then
  ok "native sidecar logged its start banner"
else
  bad "could not read the native sidecar's logs with -c shipper"
fi

head1 "7. Failure injection: independent volumeMounts"
if kubectl -n "${NS}" get pod depot-sidecar-broken >/dev/null 2>&1; then
  bad "depot-sidecar-broken exists — it should have been REJECTED at admission"
else
  # --dry-run=server runs the full admission chain but persists nothing.
  ERR="$(kubectl apply --dry-run=server \
    -f "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/manifests/90-sidecar-broken-volume.yaml" 2>&1)"
  case "${ERR}" in
    *'volumeMounts[0].name: Not found: "applogs"'*)
      ok "the API server rejects the broken manifest with the expected field-path error" ;;
    *)
      bad "unexpected result applying the broken manifest: ${ERR}" ;;
  esac
fi

echo
echo "Result: ${PASS} passed, ${FAIL} failed"
[ "${FAIL}" -eq 0 ]
