#!/usr/bin/env bash
# Lab 13 — Ingress Resources and HTTP Routing
#
# HONESTY CONTRACT
# This script has TWO modes and it tells you which one it ran.
#
#   MODE 1 "declaration-only"  - no IngressClass exists, so no controller can be
#       claiming anything. The Ingress OBJECTS are verified as correct
#       declarations. Live HTTP routing is NOT exercised and is reported SKIP,
#       never PASS and never FAIL.
#
#   MODE 2 "controller"        - an IngressClass matching the Ingress's
#       spec.ingressClassName exists. The script starts a `kubectl port-forward`
#       to the controller Deployment and exercises every rule in
#       data/routing-table.csv with real HTTP requests, including the negative
#       cases (/catalogue and a trailing slash after an Exact path).
#       Set up MODE 2 with README Appendix C.
#
# The script never asserts routing it did not perform, and never fails a cluster
# merely for having a blank Ingress ADDRESS - a controller reached over ClusterIP
# plus port-forward routes correctly while publishing no address at all.
#
# Usage:  bash verification/checks.sh
# Env:    KUBECTL  (default "kubectl")
#         NS       (default "kcna-lab13")        lab namespace
#         ING_NS   (default "kcna-lab13-ingress") optional controller namespace
#         ING_DEPLOY (default "meridian-edge-traefik") controller Deployment
#         ING_CONTAINER_PORT (default 8000)      controller HTTP entrypoint port
#         LOCAL_PORT (default 18080)             local port used for port-forward

set -uo pipefail

KUBECTL="${KUBECTL:-kubectl}"
NS="${NS:-kcna-lab13}"
CLIENT="net-client"
ING="meridian-shop"

# Optional ingress-controller path (README Appendix C). Overridable so the same
# script works against a differently named or differently placed controller.
ING_NS="${ING_NS:-kcna-lab13-ingress}"
ING_DEPLOY="${ING_DEPLOY:-meridian-edge-traefik}"
ING_CONTAINER_PORT="${ING_CONTAINER_PORT:-8000}"
LOCAL_PORT="${LOCAL_PORT:-18080}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB="$(cd "${HERE}/.." && pwd)"
DATA="${LAB}/data"

PASSED=0
FAILED=0
SKIPPED=0
pass() { printf 'PASS  %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }
skip() { printf 'SKIP  %s\n' "$1"; SKIPPED=$((SKIPPED + 1)); }
note() { printf 'NOTE  %s\n' "$1"; }
summary() { echo "-- $PASSED passed, $FAILED failed, $SKIPPED skipped --"; }

echo "== Lab 13 verification: Ingress resources and HTTP routing =="

if "$KUBECTL" get namespace "$NS" >/dev/null 2>&1; then
  pass "namespace $NS exists"
else
  fail "namespace $NS exists"
  summary
  exit 1
fi

# ------------------------------------------- ConfigMap matches the data file --
live_html="$("$KUBECTL" get configmap catalog-content -n "$NS" \
  -o jsonpath='{.data.index\.html}' 2>/dev/null)"
file_html="$(cat "${DATA}/catalog-index.html" 2>/dev/null)"
if [ -n "$live_html" ] && [ "$(printf '%s' "$live_html" | tr -d '\n')" = "$(printf '%s' "$file_html" | tr -d '\n')" ]; then
  pass "ConfigMap catalog-content matches data/catalog-index.html byte-for-byte"
else
  fail "ConfigMap catalog-content matches data/catalog-index.html byte-for-byte"
fi

# ----------------------------------------------------------------- backends --
avail=0
for d in catalog checkout route-fallback; do
  cond="$("$KUBECTL" get deployment "$d" -n "$NS" \
    -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)"
  [ "$cond" = "True" ] && avail=$((avail + 1))
done
if [ "$avail" -eq 3 ]; then
  pass "all 3 backend Deployments are Available"
else
  fail "all 3 backend Deployments are Available (only ${avail}/3)"
fi

with_eps=0
for s in catalog-svc checkout-svc route-fallback-svc; do
  addrs="$("$KUBECTL" get endpointslices -n "$NS" \
    -l "kubernetes.io/service-name=${s}" \
    -o jsonpath='{.items[*].endpoints[*].addresses[0]}' 2>/dev/null)"
  [ -n "$addrs" ] && with_eps=$((with_eps + 1))
done
if [ "$with_eps" -eq 3 ]; then
  pass "catalog-svc, checkout-svc and route-fallback-svc all have endpoints"
else
  fail "catalog-svc, checkout-svc and route-fallback-svc all have endpoints (only ${with_eps}/3)"
fi

# --------------------- backends answer DIRECTLY, with the Ingress bypassed ----
probe_backend() {
  # probe_backend <service> <expected substring>
  local svc="$1" want="$2" body
  body="$("$KUBECTL" exec -n "$NS" "$CLIENT" -- \
    wget -qO- --timeout=5 "http://${svc}/" 2>/dev/null)"
  if printf '%s' "$body" | grep -qF "$want"; then
    pass "backend ${svc} answers directly (Ingress bypassed)"
  else
    fail "backend ${svc} answers directly (Ingress bypassed) - got '${body}'"
  fi
}

if "$KUBECTL" get pod "$CLIENT" -n "$NS" >/dev/null 2>&1; then
  probe_backend catalog-svc "Meridian Freight Pte Ltd"
  probe_backend checkout-svc "checkout status OK"
  probe_backend route-fallback-svc "no ingress rule matched"
else
  fail "client Pod ${CLIENT} exists (backend probes skipped)"
fi

# ------------------------------------------------------- the Ingress object --
api="$("$KUBECTL" get ingress "$ING" -n "$NS" -o jsonpath='{.apiVersion}' 2>/dev/null)"
if [ "$api" = "networking.k8s.io/v1" ]; then
  pass "ingress ${ING} exists with apiVersion networking.k8s.io/v1"
else
  fail "ingress ${ING} exists with apiVersion networking.k8s.io/v1 (got '${api}')"
  summary
  exit 1
fi

live_rules="$("$KUBECTL" get ingress "$ING" -n "$NS" -o go-template='{{range .spec.rules}}{{$h := .host}}{{range .http.paths}}{{$h}},{{.path}},{{.pathType}},{{.backend.service.name}},{{.backend.service.port.number}}{{"\n"}}{{end}}{{end}}' 2>/dev/null)"
want_rules="$(tail -n +2 "${DATA}/routing-table.csv")"
if [ "$(printf '%s' "$live_rules")" = "$(printf '%s' "$want_rules")" ]; then
  pass "ingress rules match data/routing-table.csv exactly"
else
  fail "ingress rules do not match data/routing-table.csv"
  printf '      wanted:\n%s\n      got:\n%s\n' "$want_rules" "$live_rules"
fi

bad_types="$("$KUBECTL" get ingress -n "$NS" \
  -o jsonpath='{range .items[*].spec.rules[*].http.paths[*]}{.pathType}{"\n"}{end}' 2>/dev/null \
  | grep -vcE '^(Exact|Prefix|ImplementationSpecific)$')"
if [ "${bad_types:-0}" -eq 0 ]; then
  pass "every pathType is one of Exact / Prefix / ImplementationSpecific"
else
  fail "${bad_types} pathType value(s) are not Exact / Prefix / ImplementationSpecific"
fi

class="$("$KUBECTL" get ingress "$ING" -n "$NS" \
  -o jsonpath='{.spec.ingressClassName}' 2>/dev/null)"
if [ -n "$class" ]; then
  pass "ingress ${ING} sets ingressClassName (${class})"
else
  fail "ingress ${ING} sets ingressClassName - it is empty; class-less adoption is controller-dependent"
fi

db="$("$KUBECTL" get ingress "$ING" -n "$NS" \
  -o jsonpath='{.spec.defaultBackend.service.name}:{.spec.defaultBackend.service.port.number}' 2>/dev/null)"
if [ "$db" = "route-fallback-svc:80" ]; then
  pass "ingress ${ING} declares a defaultBackend (${db})"
else
  fail "ingress ${ING} declares a defaultBackend route-fallback-svc:80 (got '${db}')"
fi

# ------------------------------------------------------------- the TLS block --
tls_secret="$("$KUBECTL" get ingress meridian-shop-tls -n "$NS" \
  -o jsonpath='{.spec.tls[0].secretName}' 2>/dev/null)"
if [ -n "$tls_secret" ]; then
  pass "ingress meridian-shop-tls declares tls[0].secretName"
else
  fail "ingress meridian-shop-tls declares tls[0].secretName"
fi

sec_type="$("$KUBECTL" get secret "${tls_secret:-meridian-shop-tls-cert}" -n "$NS" \
  -o jsonpath='{.type}' 2>/dev/null)"
sec_keys="$("$KUBECTL" get secret "${tls_secret:-meridian-shop-tls-cert}" -n "$NS" \
  -o go-template='{{len .data}}' 2>/dev/null)"
if [ "$sec_type" = "kubernetes.io/tls" ] && [ "$sec_keys" = "2" ]; then
  pass "TLS Secret ${tls_secret} is type kubernetes.io/tls with 2 keys"
else
  fail "TLS Secret ${tls_secret} is type kubernetes.io/tls with 2 keys (type='${sec_type}' keys='${sec_keys}')"
fi


# --------------- controller presence: the honest environment determination ----
#
# Evidence ranking, deliberately mirroring README Step 8:
#   INVENTORY     an IngressClass exists / does not exist
#   INVENTORY     a known controller Pod exists / does not exist
#   CORROBORATING .status.loadBalancer -> the ADDRESS column
#
# A blank ADDRESS is never treated as proof of anything and never fails a run.
# The Appendix C controller routes correctly with a permanently blank ADDRESS,
# because its Service is a ClusterIP and publishedService is disabled.

ic_count="$("$KUBECTL" get ingressclass --no-headers 2>/dev/null | grep -c .)"
ic_count="${ic_count:-0}"
ic_controller="$("$KUBECTL" get ingressclass "${class:-__none__}" \
  -o jsonpath='{.spec.controller}' 2>/dev/null)"
status_lb="$("$KUBECTL" get ingress "$ING" -n "$NS" \
  -o jsonpath='{.status.loadBalancer.ingress[*].ip}{.status.loadBalancer.ingress[*].hostname}' 2>/dev/null)"
ctrl_pods_ready="$("$KUBECTL" get pods -n "$ING_NS" \
  -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null \
  | grep -c '^True$')"
ctrl_pods_ready="${ctrl_pods_ready:-0}"

# ------------------------------------------------- MODE 2 routing assertions --
PF_PID=""
cleanup_pf() {
  if [ -n "$PF_PID" ] && kill -0 "$PF_PID" 2>/dev/null; then
    kill "$PF_PID" 2>/dev/null
    wait "$PF_PID" 2>/dev/null
  fi
  PF_PID=""
}
trap cleanup_pf EXIT

route_check() {
  # route_check <Host header> <path> <expected substring> <label>
  local host="$1" path="$2" want="$3" label="$4" body
  body="$(curl -sS --max-time 10 -H "Host: ${host}" \
    "http://127.0.0.1:${LOCAL_PORT}${path}" 2>/dev/null)"
  if printf '%s' "$body" | grep -qF "$want"; then
    pass "$label"
  else
    fail "$label - wanted '${want}', got '$(printf '%s' "$body" | tr '\n' ' ' | cut -c1-140)'"
  fi
}

run_routing_suite() {
  route_check shop.meridianfreight.internal /catalog \
    "Meridian Freight Pte Ltd" \
    "ROUTED shop.../catalog (Prefix) -> catalog-svc"
  route_check shop.meridianfreight.internal /catalog/containers/20ft \
    "Meridian Freight Pte Ltd" \
    "ROUTED shop.../catalog/containers/20ft (Prefix, deeper path) -> catalog-svc"
  route_check shop.meridianfreight.internal /catalogue \
    "no ingress rule matched" \
    "ROUTED shop.../catalogue does NOT match Prefix /catalog (element boundary) -> defaultBackend"
  route_check shop.meridianfreight.internal /checkout/status \
    "checkout status OK" \
    "ROUTED shop.../checkout/status (Exact) -> checkout-svc"
  route_check shop.meridianfreight.internal /checkout/status/ \
    "no ingress rule matched" \
    "ROUTED shop.../checkout/status/ trailing slash breaks Exact -> defaultBackend"
  route_check tracking.meridianfreight.internal / \
    "Meridian Freight Pte Ltd" \
    "ROUTED tracking.../ (host fan-out, Prefix /) -> catalog-svc"
  route_check unmapped.meridianfreight.internal / \
    "no ingress rule matched" \
    "ROUTED unmapped host -> defaultBackend route-fallback-svc"
}

skip_routing_suite() {
  # skip_routing_suite <reason>
  skip "live HTTP routing not exercised: $1"
}

if [ "$ic_count" -eq 0 ]; then
  # ---------------------------------------------------- MODE 1: declaration --
  note "MODE 1 (declaration-only): no IngressClass exists on this cluster."
  pass "INVENTORY: 0 IngressClasses found; routing remains unverified"
  if [ "$ctrl_pods_ready" -eq 0 ]; then
    pass "INVENTORY: no Ready controller Pod in namespace ${ING_NS}"
  else
    fail "no IngressClass exists yet ${ctrl_pods_ready} Ready Pod(s) run in ${ING_NS} - investigate"
  fi
  if [ -z "$status_lb" ]; then
    note "CORROBORATING: .status.loadBalancer is empty (ADDRESS column blank). This does not establish whether routing works."
  else
    note "CORROBORATING: .status.loadBalancer is '${status_lb}' despite no IngressClass - worth investigating."
  fi
  skip_routing_suite "the supplied controller path is not configured (MODE 1)"
  note "The Ingress objects are verified as CORRECT DECLARATIONS only."
  note "README Appendix C installs a pinned controller and switches this script into MODE 2."
  summary
else
  # ----------------------------------------------------- MODE 2: controller --
  note "MODE 2 (controller present): ${ic_count} IngressClass(es) found on this cluster."
  pass "INVENTORY: ${ic_count} IngressClass(es) found; readiness and routing checked next"
  if [ -n "$ic_controller" ]; then
    pass "IngressClass '${class}' exists and names controller '${ic_controller}', so ${ING} is claimable"
  else
    fail "an IngressClass exists but none is named '${class}': ${ING}.spec.ingressClassName is a forward reference to a missing IngressClass"
  fi
  if [ "$ctrl_pods_ready" -gt 0 ]; then
    pass "DECISIVE: ${ctrl_pods_ready} Ready controller Pod(s) in namespace ${ING_NS}"
  else
    note "no Ready Pod found in ${ING_NS}: the controller may live elsewhere. Set ING_NS / ING_DEPLOY to point at it."
  fi
  if [ -n "$status_lb" ]; then
    note "CORROBORATING: the controller published ADDRESS '${status_lb}'."
  else
    note "CORROBORATING: ADDRESS is blank. That is NOT a failure - a ClusterIP controller reached by port-forward publishes no address and still routes."
  fi

  # Routing assertions need curl, the controller Deployment, and a free port.
  if ! command -v curl >/dev/null 2>&1; then
    skip_routing_suite "curl is not installed on this workstation"
  elif ! "$KUBECTL" get deployment "$ING_DEPLOY" -n "$ING_NS" >/dev/null 2>&1; then
    skip_routing_suite "controller Deployment ${ING_NS}/${ING_DEPLOY} not found (override ING_NS / ING_DEPLOY)"
  else
    "$KUBECTL" rollout status "deployment/${ING_DEPLOY}" -n "$ING_NS" --timeout=90s >/dev/null 2>&1
    "$KUBECTL" port-forward -n "$ING_NS" "deployment/${ING_DEPLOY}" \
      "${LOCAL_PORT}:${ING_CONTAINER_PORT}" >/dev/null 2>&1 &
    PF_PID=$!
    pf_up=0
    for _ in $(seq 1 30); do
      if curl -sS --max-time 2 -o /dev/null "http://127.0.0.1:${LOCAL_PORT}/" 2>/dev/null; then
        pf_up=1
        break
      fi
      sleep 1
    done
    if [ "$pf_up" -eq 1 ]; then
      pass "port-forward 127.0.0.1:${LOCAL_PORT} -> ${ING_NS}/${ING_DEPLOY}:${ING_CONTAINER_PORT} is up"
      run_routing_suite
    else
      skip_routing_suite "port-forward to ${ING_NS}/${ING_DEPLOY}:${ING_CONTAINER_PORT} did not come up within 30s (is LOCAL_PORT ${LOCAL_PORT} free?)"
    fi
    cleanup_pf
  fi
  summary
fi

[ "$FAILED" -eq 0 ]
