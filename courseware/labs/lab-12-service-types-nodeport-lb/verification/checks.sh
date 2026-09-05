#!/usr/bin/env bash
# Lab 12 — Service Types: ClusterIP, NodePort and LoadBalancer
# Every assertion is driven by data/service-matrix.csv, including the assertion
# that the LoadBalancer EXTERNAL-IP is STILL <pending>. On a kind cluster that
# pending state is the correct outcome, so the check passes when it is pending
# and fails only if the file and the cluster disagree.
# Usage:  bash verification/checks.sh
# Env:    KUBECTL (default "kubectl"), NS (default "kcna-lab12")

set -uo pipefail

KUBECTL="${KUBECTL:-kubectl}"
NS="${NS:-kcna-lab12}"
CLIENT="net-client"
APP_LABEL="app=booking-edge"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB="$(cd "${HERE}/.." && pwd)"
DATA="${LAB}/data"

PASSED=0
FAILED=0
pass() { printf 'PASS  %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

in_nodeport_range() {
  # in_nodeport_range <port> -- default --service-node-port-range is 30000-32767
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -ge 30000 ] && [ "$1" -le 32767 ]
}

echo "== Lab 12 verification: Service types on kind =="

if "$KUBECTL" get namespace "$NS" >/dev/null 2>&1; then
  pass "namespace $NS exists"
else
  fail "namespace $NS exists"
  echo "-- $PASSED passed, $FAILED failed --"
  exit 1
fi

ready="$("$KUBECTL" get deployment booking-edge -n "$NS" \
  -o jsonpath='{.status.readyReplicas}' 2>/dev/null)"
ready="${ready:-0}"
if [ "$ready" = "2" ]; then
  pass "deployment booking-edge has 2/2 ready replicas"
else
  fail "deployment booking-edge has 2/2 ready replicas (got ${ready})"
fi

# ------------------------------------- drive every check from the CSV matrix --
while IFS=',' read -r m_name m_type m_clusterip m_port m_target m_nodeport m_extip _rest; do
  [ -z "${m_name:-}" ] && continue
  [ "$m_name" = "name" ] && continue

  if ! "$KUBECTL" get service "$m_name" -n "$NS" >/dev/null 2>&1; then
    fail "matrix row ${m_name}: Service does not exist"
    continue
  fi

  got_type="$("$KUBECTL" get service "$m_name" -n "$NS" -o jsonpath='{.spec.type}' 2>/dev/null)"
  got_port="$("$KUBECTL" get service "$m_name" -n "$NS" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)"
  got_target="$("$KUBECTL" get service "$m_name" -n "$NS" -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)"
  if [ "$got_type" = "$m_type" ] && [ "$got_port" = "$m_port" ] && [ "$got_target" = "$m_target" ]; then
    pass "matrix row ${m_name}: type=${m_type} port=${m_port} targetPort=${m_target}"
  else
    fail "matrix row ${m_name}: expected type=${m_type} port=${m_port} targetPort=${m_target}, got type=${got_type} port=${got_port} targetPort=${got_target}"
  fi

  got_cip="$("$KUBECTL" get service "$m_name" -n "$NS" -o jsonpath='{.spec.clusterIP}' 2>/dev/null)"
  if [ "$m_clusterip" = "None" ]; then
    if [ "$got_cip" = "None" ]; then
      pass "matrix row ${m_name}: clusterIP is None as expected"
    else
      fail "matrix row ${m_name}: clusterIP should be None, got '${got_cip}'"
    fi
  else
    if [ -n "$got_cip" ] && [ "$got_cip" != "None" ]; then
      pass "matrix row ${m_name}: clusterIP allocated as expected"
    else
      fail "matrix row ${m_name}: clusterIP should be allocated, got '${got_cip}'"
    fi
  fi

  got_np="$("$KUBECTL" get service "$m_name" -n "$NS" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)"
  case "$m_nodeport" in
    none)
      if [ -z "$got_np" ]; then
        pass "matrix row ${m_name}: no nodePort allocated, as expected"
      else
        fail "matrix row ${m_name}: expected no nodePort, got ${got_np}"
      fi
      ;;
    auto)
      if in_nodeport_range "$got_np"; then
        pass "matrix row ${m_name}: auto-allocated nodePort ${got_np} is inside 30000-32767"
      else
        fail "matrix row ${m_name}: auto-allocated nodePort '${got_np}' is not inside 30000-32767"
      fi
      ;;
    *)
      if [ "$got_np" = "$m_nodeport" ]; then
        pass "matrix row ${m_name}: nodePort is ${m_nodeport}"
      else
        fail "matrix row ${m_name}: expected nodePort ${m_nodeport}, got '${got_np}'"
      fi
      if in_nodeport_range "$got_np"; then
        pass "matrix row ${m_name}: nodePort ${got_np} is inside 30000-32767"
      else
        fail "matrix row ${m_name}: nodePort '${got_np}' is not inside 30000-32767"
      fi
      ;;
  esac

  if [ "$m_extip" = "pending-forever" ]; then
    got_ing="$("$KUBECTL" get service "$m_name" -n "$NS" \
      -o jsonpath='{.status.loadBalancer.ingress[*].ip}{.status.loadBalancer.ingress[*].hostname}' 2>/dev/null)"
    if [ -z "$got_ing" ]; then
      pass "EXPECTED ON kind: ${m_name} EXTERNAL-IP is still <pending> (no cloud-controller-manager)"
    else
      fail "${m_name} unexpectedly has an external address '${got_ing}' - this cluster is NOT stock kind, so revisit data/service-matrix.csv"
    fi
  fi
done < "${DATA}/service-matrix.csv"

# ------------------------------ every type shares the same backend addresses --
pod_ips="$("$KUBECTL" get pods -n "$NS" -l "$APP_LABEL" \
  -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' 2>/dev/null | sort | tr '\n' ' ')"
same=1
for svc in booking-edge-clusterip booking-edge-nodeport booking-edge-lb booking-edge-headless; do
  slice_ips="$("$KUBECTL" get endpointslices -n "$NS" \
    -l "kubernetes.io/service-name=${svc}" \
    -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{"\n"}{end}' 2>/dev/null | sort | tr '\n' ' ')"
  [ "$slice_ips" = "$pod_ips" ] || same=0
done
if [ "$same" -eq 1 ] && [ -n "$pod_ips" ]; then
  pass "all four Services resolve to the same 2 endpoint addresses"
else
  fail "all four Services resolve to the same 2 endpoint addresses (pods='${pod_ips}')"
fi

# ------------------------------------------------ reachability from a client --
if "$KUBECTL" get pod "$CLIENT" -n "$NS" >/dev/null 2>&1; then
  banner="$(tr -d '\n' < "${DATA}/edge-banner.txt")"

  body="$("$KUBECTL" exec -n "$NS" "$CLIENT" -- \
    wget -qO- --timeout=5 http://booking-edge-clusterip/ 2>/dev/null | tr -d '\n')"
  if [ "$body" = "$banner" ]; then
    pass "ClusterIP Service serves the exact text in data/edge-banner.txt"
  else
    fail "ClusterIP Service body '${body}' != data/edge-banner.txt '${banner}'"
  fi

  node_ip="$("$KUBECTL" get nodes \
    -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)"
  np="$("$KUBECTL" get service booking-edge-nodeport -n "$NS" \
    -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)"
  np_body="$("$KUBECTL" exec -n "$NS" "$CLIENT" -- \
    wget -qO- --timeout=5 "http://${node_ip}:${np}/" 2>/dev/null | tr -d '\n')"
  if [ "$np_body" = "$banner" ]; then
    pass "NodePort ${np} answers on the node InternalIP from inside the cluster"
  else
    fail "NodePort ${np} on ${node_ip} did not return the banner (got '${np_body}')"
  fi

  # Headless: query the FULL FQDN. BusyBox nslookup does not walk the search
  # list for dotted partial names, so only an absolute name is reliable here.
  fqdn="booking-edge-headless.${NS}.svc.cluster.local"
  answers="$("$KUBECTL" exec -n "$NS" "$CLIENT" -- nslookup "$fqdn" 2>/dev/null \
    | awk '/[Aa]ddress/ {print $NF}' | grep -v ':' | sort | tr '\n' ' ')"
  if [ -n "$answers" ] && [ "$answers" = "$pod_ips" ]; then
    pass "headless Service DNS returns Pod IPs, not a virtual IP"
  else
    fail "headless Service DNS returned '${answers}', expected the Pod IPs '${pod_ips}'"
  fi
else
  fail "client Pod ${CLIENT} exists (reachability checks skipped)"
fi

echo "-- $PASSED passed, $FAILED failed --"
[ "$FAILED" -eq 0 ]
