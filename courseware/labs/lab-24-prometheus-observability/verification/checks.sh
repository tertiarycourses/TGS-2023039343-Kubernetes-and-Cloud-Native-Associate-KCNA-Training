#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Lab 24 — Metrics, Prometheus Exposition and the Observability Pipeline
# Meridian Freight Pte Ltd · Depot Portal platform
#
# Read-only against the cluster: it GETs /metrics and the Prometheus query API
# and creates, patches and deletes nothing.
#
# Run:  bash verification/checks.sh
# ---------------------------------------------------------------------------
set -uo pipefail

NS="${NS:-kcna-lab24}"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENT="metrics-client"
SIM_URL="http://depot-metrics-sim.${NS}.svc.cluster.local:9100/metrics"
PROM="http://prometheus.${NS}.svc.cluster.local:9090"
PASS=0
FAIL=0
SKIP=0

ok()    { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad()   { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
skip()  { printf '  SKIP  %s\n' "$1"; SKIP=$((SKIP + 1)); }
head2() { printf '\n== %s\n' "$1"; }

# Run a wget inside the in-cluster client Pod.
inpod() { kubectl exec -n "$NS" "$CLIENT" -- wget -qO- "$1" 2>/dev/null; }

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

head2 "Part 2 — ConfigMaps sourced from data/"
for pair in "depot-metrics-generator generate-metrics.sh" \
            "prometheus-config prometheus.yml"; do
  set -- $pair
  cm="$1"; key="$2"
  if kubectl get configmap "$cm" -n "$NS" >/dev/null 2>&1; then
    ok "configmap/$cm exists"
    content="$(kubectl get configmap "$cm" -n "$NS" \
      -o "go-template={{index .data \"$key\"}}" 2>/dev/null)"
    if [ -n "$content" ] && [ "$content" != '<no value>' ]; then
      ok "configmap/$cm key '$key' is populated"
    else
      bad "configmap/$cm key '$key' is missing or empty (the key name matters)"
    fi
  else
    bad "configmap/$cm missing — see Steps 2.2 and 4.3"
  fi
done

head2 "Part 2 — scrape target workload"
if kubectl get deployment depot-metrics-sim -n "$NS" >/dev/null 2>&1; then
  ok "deployment/depot-metrics-sim exists"

  replicas=$(kubectl get deployment depot-metrics-sim -n "$NS" \
    -o jsonpath='{.spec.replicas}' 2>/dev/null)
  if [ "${replicas:-0}" = "1" ]; then
    ok "replicas=1 (required: scraping through a Service with >1 replica makes counters jump backwards)"
  else
    bad "replicas=${replicas:-?} — counters will appear to reset; see Step 6 and the Troubleshooting table"
  fi

  for c in generator exporter; do
    if kubectl get deployment depot-metrics-sim -n "$NS" \
         -o jsonpath='{.spec.template.spec.containers[*].name}' | grep -qw "$c"; then
      ok "container '$c' present"
    else
      bad "container '$c' missing"
    fi
  done

  imgs=$(kubectl get deployment depot-metrics-sim -n "$NS" \
    -o jsonpath='{.spec.template.spec.containers[*].image}')
  if printf '%s' "$imgs" | grep -q ':latest'; then
    bad "an image uses :latest — all images must be pinned ($imgs)"
  else
    ok "all target images pinned ($imgs)"
  fi
else
  bad "deployment/depot-metrics-sim missing — see Step 2.3"
fi

head2 "Part 3 — exposition format served over HTTP"
if kubectl get pod "$CLIENT" -n "$NS" >/dev/null 2>&1; then
  ok "pod/$CLIENT exists"
  body="$(inpod "$SIM_URL")"
  if [ -n "$body" ]; then
    ok "/metrics returns a non-empty body"

    printf '%s\n' "$body" | grep -q '^# HELP depot_portal_shipments_scanned_total' \
      && ok "# HELP line present for the counter" \
      || bad "# HELP line missing — exposition metadata is required"

    printf '%s\n' "$body" | grep -q '^# TYPE depot_portal_shipments_scanned_total counter' \
      && ok "# TYPE declares the counter" \
      || bad "# TYPE counter line missing"

    printf '%s\n' "$body" | grep -q '^# TYPE depot_portal_queue_depth gauge' \
      && ok "# TYPE declares the gauge" \
      || bad "# TYPE gauge line missing"

    printf '%s\n' "$body" | grep -q '^# TYPE depot_portal_scan_latency_seconds histogram' \
      && ok "# TYPE declares the histogram" \
      || bad "# TYPE histogram line missing"

    printf '%s\n' "$body" | grep -q 'depot_portal_scan_latency_seconds_bucket.*le="+Inf"' \
      && ok "histogram has the mandatory le=\"+Inf\" bucket" \
      || bad "le=\"+Inf\" bucket missing — the histogram is malformed"

    # le="+Inf" must equal _count. This is a structural invariant, not a value
    # prediction, so it is safe to assert.
    inf=$(printf '%s\n' "$body" \
      | grep 'scan_latency_seconds_bucket.*le="+Inf"' | awk '{print $NF}')
    cnt=$(printf '%s\n' "$body" \
      | grep '^depot_portal_scan_latency_seconds_count' | awk '{print $NF}')
    if [ -n "$inf" ] && [ "$inf" = "$cnt" ]; then
      ok "le=\"+Inf\" ($inf) equals _count ($cnt) as the format requires"
    else
      bad "le=\"+Inf\" ($inf) does not equal _count ($cnt) — malformed histogram"
    fi

    printf '%s\n' "$body" | grep -q 'depot_portal_build_info{version="6.0.0"' \
      && ok "_info pattern present (value 1, labels carry the data)" \
      || bad "depot_portal_build_info missing"
  else
    bad "/metrics returned nothing — is depot-metrics-sim Ready?"
  fi

  # Counters must increase between two scrapes. Structural, not a fixed value.
  v1=$(inpod "$SIM_URL" | grep '^depot_portal_shipments_scanned_total' | awk '{print $NF}')
  sleep 12
  v2=$(inpod "$SIM_URL" | grep '^depot_portal_shipments_scanned_total' | awk '{print $NF}')
  if [ -n "$v1" ] && [ -n "$v2" ] && [ "$v2" -gt "$v1" ] 2>/dev/null; then
    ok "counter increased across two scrapes ($v1 -> $v2)"
  else
    bad "counter did not increase ($v1 -> $v2) — is the generator container running?"
  fi
else
  bad "pod/$CLIENT missing — see Step 3.1"
fi

head2 "Part 4 — Prometheus and its targets"
if kubectl get deployment prometheus -n "$NS" >/dev/null 2>&1; then
  ok "deployment/prometheus exists"

  img=$(kubectl get deployment prometheus -n "$NS" \
    -o jsonpath='{.spec.template.spec.containers[0].image}')
  case "$img" in
    *:latest|"") bad "prometheus image must be pinned, got '${img:-<unset>}'" ;;
    *:*)         ok "prometheus image is pinned ($img)" ;;
    *)           bad "prometheus image has no tag" ;;
  esac

  if kubectl get deployment prometheus -n "$NS" \
       -o jsonpath='{.spec.template.spec.containers[0].args}' \
       | grep -q 'web.enable-lifecycle'; then
    ok "--web.enable-lifecycle set (needed for the Part 6 hot reload)"
  else
    bad "--web.enable-lifecycle missing — POST /-/reload will 404"
  fi

  ready=$(kubectl get deployment prometheus -n "$NS" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  if [ "${ready:-0}" -ge 1 ] 2>/dev/null; then
    ok "prometheus is Ready"

    targets="$(inpod "${PROM}/api/v1/targets?state=active")"
    if printf '%s' "$targets" | grep -q '"job":"depot-portal"'; then
      ok "job 'depot-portal' is configured"
    else
      bad "job 'depot-portal' not found in active targets"
    fi
    if printf '%s' "$targets" | grep -q '"job":"prometheus"'; then
      ok "job 'prometheus' (self-scrape) is configured"
    else
      bad "job 'prometheus' not found in active targets"
    fi

    down=$(printf '%s' "$targets" | tr ',' '\n' | grep -c '"health":"down"' || true)
    if [ "${down:-0}" -eq 0 ]; then
      ok "no targets are DOWN"
    else
      bad "$down target(s) DOWN — if you are mid-Part-6 this is expected; finish Step 6.8"
    fi

    up="$(inpod "${PROM}/api/v1/query?query=up")"
    if printf '%s' "$up" | grep -q '"status":"success"'; then
      ok "PromQL query API responds"
    else
      bad "PromQL query API did not return success"
    fi

    r="$(inpod "${PROM}/api/v1/query?query=rate(depot_portal_shipments_scanned_total%5B2m%5D)")"
    if printf '%s' "$r" | grep -q '"result":\[{'; then
      ok "rate() over the counter returns a non-empty result"
    else
      skip "rate() empty — allow ~2 minutes of scrape history after Step 4.4, then re-run"
    fi

    h="$(inpod "${PROM}/api/v1/query?query=histogram_quantile(0.95%2C%20sum%20by%20(le)%20(rate(depot_portal_scan_latency_seconds_bucket%5B5m%5D)))")"
    if printf '%s' "$h" | grep -q '"result":\[{'; then
      if printf '%s' "$h" | grep -q 'NaN'; then
        bad "histogram_quantile returned NaN — check that 'le' survives the sum by clause"
      else
        ok "histogram_quantile(0.95, ...) returns a value"
      fi
    else
      skip "histogram_quantile empty — needs ~5 minutes of history; re-run later"
    fi
  else
    bad "prometheus not Ready yet — wait and re-run"
  fi
else
  bad "deployment/prometheus missing — see Step 4.4"
fi

head2 "Worksheet"
WS="$LAB_DIR/data/exposition-worksheet.csv"
if [ -f "$WS" ]; then
  ok "worksheet present at data/exposition-worksheet.csv"
  if head -1 "$WS" | grep -q 'expected_band'; then
    ok "worksheet header intact"
  else
    bad "worksheet header has been altered"
  fi
else
  bad "worksheet missing at $WS"
fi

head2 "Scope guard"
if kubectl get crd 2>/dev/null | grep -qi 'servicemonitor\|podmonitor'; then
  skip "Prometheus Operator CRDs exist on this cluster (not created by this lab)"
else
  ok "no Prometheus Operator CRDs — this lab is deliberately Operator-free"
fi

if kubectl get deploy,po,svc -n kube-system \
     -l kcna.tertiaryinfotech.com/lab=lab-24 2>/dev/null | grep -q .; then
  bad "this lab created objects in kube-system — it must not"
else
  ok "no lab-24 objects in kube-system"
fi

printf '\nSUMMARY: %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
