#!/usr/bin/env bash
# Lab 11 — Services, Endpoints and Cluster DNS
# Verification checks. Read-only apart from `kubectl exec` into the dns-client Pod.
# Usage:  bash verification/checks.sh
# Env:    KUBECTL (default "kubectl"), NS (default "kcna-lab11")

set -uo pipefail

KUBECTL="${KUBECTL:-kubectl}"
NS="${NS:-kcna-lab11}"
SVC="quote-api"
CLIENT="dns-client"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB="$(cd "${HERE}/.." && pwd)"
DATA="${LAB}/data"

PASSED=0
FAILED=0

pass() { printf 'PASS  %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

check() {
  # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass "$1"
  else
    fail "$1 (expected '$2', got '$3')"
  fi
}

echo "== Lab 11 verification: Services, Endpoints and Cluster DNS =="

# ---------------------------------------------------------------- namespace --
if "$KUBECTL" get namespace "$NS" >/dev/null 2>&1; then
  pass "namespace $NS exists"
else
  fail "namespace $NS exists"
  echo "-- $PASSED passed, $FAILED failed --"
  exit 1
fi

# ------------------------------------------- ConfigMap matches the data file --
live_html="$("$KUBECTL" get configmap quote-api-content -n "$NS" \
  -o jsonpath='{.data.index\.html}' 2>/dev/null)"
file_html="$(cat "${DATA}/quote-api-index.html" 2>/dev/null)"
if [ -n "$live_html" ] && [ "$(printf '%s' "$live_html" | tr -d '\n')" = "$(printf '%s' "$file_html" | tr -d '\n')" ]; then
  pass "ConfigMap quote-api-content matches data/quote-api-index.html byte-for-byte"
else
  fail "ConfigMap quote-api-content matches data/quote-api-index.html byte-for-byte"
fi

# --------------------------------------------------------------- Deployment --
ready="$("$KUBECTL" get deployment "$SVC" -n "$NS" \
  -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
ready="${ready:-0}"
check "deployment $SVC has 3/3 ready replicas" "3" "$ready"

# ------------------------------------------------------------------ Service --
svc_type="$("$KUBECTL" get service "$SVC" -n "$NS" -o jsonpath='{.spec.type}' 2>/dev/null)"
svc_port="$("$KUBECTL" get service "$SVC" -n "$NS" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)"
if [ "$svc_type" = "ClusterIP" ] && [ "$svc_port" = "80" ]; then
  pass "service $SVC is ClusterIP with port 80"
else
  fail "service $SVC is ClusterIP with port 80 (type='$svc_type' port='$svc_port')"
fi

tgt="$("$KUBECTL" get service "$SVC" -n "$NS" \
  -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)"
check 'service quote-api targetPort is the named port "http"' "http" "$tgt"

# ------------------------------------------------------------- EndpointSlice --
sel="kubernetes.io/service-name=${SVC}"
slice_port="$("$KUBECTL" get endpointslices -n "$NS" -l "$sel" \
  -o jsonpath='{.items[0].ports[0].port}' 2>/dev/null)"
check "EndpointSlice resolved the named port to 8080" "8080" "$slice_port"

ready_eps="$("$KUBECTL" get endpointslices -n "$NS" -l "$sel" \
  -o jsonpath='{range .items[*].endpoints[*]}{.conditions.ready}{"\n"}{end}' 2>/dev/null \
  | grep -c '^true$')"
check "EndpointSlice holds 3 ready addresses" "3" "$ready_eps"

slice_ips="$("$KUBECTL" get endpointslices -n "$NS" -l "$sel" \
  -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{"\n"}{end}' 2>/dev/null \
  | sort | tr '\n' ' ')"
pod_ips="$("$KUBECTL" get pods -n "$NS" -l "app=${SVC}" \
  -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' 2>/dev/null \
  | sort | tr '\n' ' ')"
if [ -n "$slice_ips" ] && [ "$slice_ips" = "$pod_ips" ]; then
  pass "EndpointSlice addresses match the quote-api Pod IPs exactly"
else
  fail "EndpointSlice addresses match the quote-api Pod IPs exactly (slice='$slice_ips' pods='$pod_ips')"
fi

# ------------------------------------------------- DNS fixtures from data/ ---
if "$KUBECTL" get pod "$CLIENT" -n "$NS" >/dev/null 2>&1; then
  # Skip the CSV header, then test every fixture row.
  while IFS=',' read -r fixture_name fixture_kind fixture_expect _rest; do
    [ -z "${fixture_name:-}" ] && continue
    [ "$fixture_name" = "name" ] && continue
    # Use the application resolver: BusyBox nslookup does not consistently
    # apply ndots/search to dotted partial names. Only inspect ping's resolved
    # IPv4 header; Service VIPs need not respond to ICMP, so ignore ping status.
    dns_output="$("$KUBECTL" exec -n "$NS" "$CLIENT" -- ping -c 1 -W 1 "$fixture_name" 2>/dev/null || true)"
    if printf '%s\n' "$dns_output" | grep -qE '^PING [^ ]+ \([0-9]{1,3}(\.[0-9]{1,3}){3}\)'; then
      got="yes"
    else
      got="no"
    fi
    if [ "$got" = "$fixture_expect" ]; then
      if [ "$fixture_expect" = "yes" ]; then
        pass "dns fixture: ${fixture_name} resolves"
      else
        pass "dns fixture: ${fixture_name} correctly does NOT resolve"
      fi
    else
      fail "dns fixture: ${fixture_name} (${fixture_kind}) expected resolves=${fixture_expect}, got ${got}"
    fi
  done < "${DATA}/dns-fixtures.csv"

  # ------------------------------------------------------ end-to-end HTTP ----
  body="$("$KUBECTL" exec -n "$NS" "$CLIENT" -- \
    wget -qO- --timeout=5 "http://${SVC}/" 2>/dev/null)"
  if printf '%s' "$body" | grep -q 'Meridian Freight Pte Ltd'; then
    pass "HTTP GET through the Service returns the Meridian Freight page"
  else
    fail "HTTP GET through the Service returns the Meridian Freight page"
  fi
else
  fail "client Pod ${CLIENT} exists (DNS and HTTP fixtures skipped)"
fi

echo "-- $PASSED passed, $FAILED failed --"
[ "$FAILED" -eq 0 ]
