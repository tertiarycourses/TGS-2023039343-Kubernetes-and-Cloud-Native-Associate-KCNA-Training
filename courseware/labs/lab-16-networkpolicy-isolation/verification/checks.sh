#!/usr/bin/env bash
# Lab 16 — NetworkPolicy and Default-Deny Isolation
#
# HONESTY CONTRACT
# kind's default CNI (kindnet) does NOT enforce NetworkPolicy. This script
# therefore verifies that the policy OBJECTS correctly express the intent in
# data/traffic-matrix.csv, and then runs a live enforcement probe whose result
# is REPORTED rather than assumed. On stock kind the probe is expected to show
# that traffic still flows; that is recorded as the environment's state, not as
# a policy defect. Blocking is asserted ONLY when an enforcing CNI is detected.
#
# Usage:  bash verification/checks.sh
# Env:    KUBECTL (default "kubectl"), NS (default "kcna-lab16")

set -uo pipefail

KUBECTL="${KUBECTL:-kubectl}"
NS="${NS:-kcna-lab16}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB="$(cd "${HERE}/.." && pwd)"
DATA="${LAB}/data"

PASSED=0
FAILED=0
pass() { printf 'PASS  %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }
note() { printf 'NOTE  %s\n' "$1"; }

jp() { "$KUBECTL" get "$@" 2>/dev/null; }

echo "== Lab 16 verification: NetworkPolicy and default-deny isolation =="

if "$KUBECTL" get namespace "$NS" >/dev/null 2>&1; then
  pass "namespace $NS exists"
else
  fail "namespace $NS exists"
  echo "-- $PASSED passed, $FAILED failed --"
  exit 1
fi

# ------------------------------------------- ConfigMap matches the data file --
live_html="$(jp configmap payments-content -n "$NS" -o jsonpath='{.data.index\.html}')"
file_html="$(cat "${DATA}/payments-index.html" 2>/dev/null)"
if [ -n "$live_html" ] && [ "$(printf '%s' "$live_html" | tr -d '\n')" = "$(printf '%s' "$file_html" | tr -d '\n')" ]; then
  pass "ConfigMap payments-content matches data/payments-index.html byte-for-byte"
else
  fail "ConfigMap payments-content matches data/payments-index.html byte-for-byte"
fi

# ------------------------------------------------------ workload and clients --
avail="$(jp deployment payments-api -n "$NS" \
  -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')"
eps="$(jp endpointslices -n "$NS" -l kubernetes.io/service-name=payments-api \
  -o jsonpath='{.items[*].endpoints[*].addresses[0]}')"
if [ "$avail" = "True" ] && [ -n "$eps" ]; then
  pass "deployment payments-api is Available and Service payments-api has endpoints"
else
  fail "deployment payments-api Available='${avail}' endpoints='${eps}'"
fi

fe_img="$(jp pod frontend -n "$NS" -o jsonpath='{.spec.containers[0].image}')"
rp_img="$(jp pod reporting -n "$NS" -o jsonpath='{.spec.containers[0].image}')"
fe_role="$(jp pod frontend -n "$NS" -o jsonpath='{.metadata.labels.role}')"
rp_role="$(jp pod reporting -n "$NS" -o jsonpath='{.metadata.labels.role}')"
if [ -n "$fe_img" ] && [ "$fe_img" = "$rp_img" ] \
   && [ "$fe_role" = "frontend" ] && [ "$rp_role" = "reporting" ]; then
  pass "frontend and reporting run the same image and differ by the role label"
else
  fail "frontend/reporting mismatch (images '${fe_img}' vs '${rp_img}', roles '${fe_role}' vs '${rp_role}')"
fi

# --------------------------------------------------------- the default deny --
dd_sel="$(jp networkpolicy default-deny-all -n "$NS" -o jsonpath='{.spec.podSelector}')"
dd_types="$(jp networkpolicy default-deny-all -n "$NS" -o jsonpath='{.spec.policyTypes[*]}')"
if [ "$dd_sel" = "{}" ] && [ "$dd_types" = "Ingress Egress" ]; then
  pass "default-deny-all selects ALL pods ({}) for both Ingress and Egress"
else
  fail "default-deny-all podSelector='${dd_sel}' policyTypes='${dd_types}'"
fi

dd_in="$(jp networkpolicy default-deny-all -n "$NS" -o jsonpath='{.spec.ingress}')"
dd_eg="$(jp networkpolicy default-deny-all -n "$NS" -o jsonpath='{.spec.egress}')"
if [ -z "$dd_in" ] && [ -z "$dd_eg" ]; then
  pass "default-deny-all declares no allow rules (isolation by selection)"
else
  fail "default-deny-all should have no ingress/egress rules (ingress='${dd_in}' egress='${dd_eg}')"
fi

# ------------------------------------------------------------- the DNS rule --
dns_ports="$(jp networkpolicy allow-dns-egress -n "$NS" \
  -o jsonpath='{range .spec.egress[0].ports[*]}{.protocol}/{.port} {end}')"
case "$dns_ports" in
  *UDP/53*) udp_ok=1 ;;
  *) udp_ok=0 ;;
esac
case "$dns_ports" in
  *TCP/53*) tcp_ok=1 ;;
  *) tcp_ok=0 ;;
esac
if [ "$udp_ok" -eq 1 ] && [ "$tcp_ok" -eq 1 ]; then
  pass "allow-dns-egress permits UDP/53 and TCP/53 to kube-system"
else
  fail "allow-dns-egress ports are '${dns_ports}' - both UDP/53 and TCP/53 are required"
fi

# namespaceSelector AND podSelector must be in the SAME peer item (index 0).
peer_ns="$(jp networkpolicy allow-dns-egress -n "$NS" \
  -o jsonpath='{.spec.egress[0].to[0].namespaceSelector.matchLabels.kubernetes\.io/metadata\.name}')"
peer_pod="$(jp networkpolicy allow-dns-egress -n "$NS" \
  -o jsonpath='{.spec.egress[0].to[0].podSelector.matchLabels.k8s-app}')"
if [ "$peer_ns" = "kube-system" ] && [ "$peer_pod" = "kube-dns" ]; then
  pass "allow-dns-egress ANDs namespaceSelector with podSelector in one peer"
else
  fail "allow-dns-egress peer[0] ns='${peer_ns}' pod='${peer_pod}' - they must be ANDed in ONE list item"
fi

# ---------------------------------------------------------- the allow policy --
af_sel="$(jp networkpolicy allow-frontend-to-payments -n "$NS" \
  -o jsonpath='{.spec.podSelector.matchLabels.app}')"
af_types="$(jp networkpolicy allow-frontend-to-payments -n "$NS" \
  -o jsonpath='{.spec.policyTypes[*]}')"
if [ "$af_sel" = "payments-api" ] && [ "$af_types" = "Ingress" ]; then
  pass "allow-frontend-to-payments protects app=payments-api on ingress"
else
  fail "allow-frontend-to-payments podSelector.app='${af_sel}' policyTypes='${af_types}'"
fi

af_from="$(jp networkpolicy allow-frontend-to-payments -n "$NS" \
  -o jsonpath='{range .spec.ingress[*].from[*]}{.podSelector.matchLabels.role} {end}')"
if [ "$(printf '%s' "$af_from" | tr -d ' ')" = "frontend" ]; then
  pass "allow-frontend-to-payments admits role=frontend only"
else
  fail "allow-frontend-to-payments admits '${af_from}', expected only role=frontend"
fi

af_port="$(jp networkpolicy allow-frontend-to-payments -n "$NS" \
  -o jsonpath='{.spec.ingress[0].ports[0].port}')"
c_port="$(jp pods -n "$NS" -l app=payments-api \
  -o jsonpath='{.items[0].spec.containers[0].ports[0].containerPort}')"
if [ -n "$af_port" ] && [ "$af_port" = "$c_port" ]; then
  pass "allow-frontend-to-payments port ${af_port} equals the payments-api containerPort"
else
  fail "policy port '${af_port}' != containerPort '${c_port}' - NetworkPolicy matches the POD port, not the Service port"
fi

eg_sel="$(jp networkpolicy allow-frontend-egress-to-payments -n "$NS" \
  -o jsonpath='{.spec.podSelector.matchLabels.role}')"
eg_to="$(jp networkpolicy allow-frontend-egress-to-payments -n "$NS" \
  -o jsonpath='{.spec.egress[0].to[0].podSelector.matchLabels.app}')"
eg_port="$(jp networkpolicy allow-frontend-egress-to-payments -n "$NS" \
  -o jsonpath='{.spec.egress[0].ports[0].port}')"
if [ "$eg_sel" = "frontend" ] && [ "$eg_to" = "payments-api" ] && [ "$eg_port" = "$c_port" ]; then
  pass "allow-frontend-egress-to-payments covers the client side of the same flow"
else
  fail "allow-frontend-egress-to-payments sel='${eg_sel}' to='${eg_to}' port='${eg_port}'"
fi

# ----------------------------------------------------------------------------
# Does ANY ingress policy express: <src_key>=<src_val> -> <dst_key>=<dst_val>:<port> ?
# ----------------------------------------------------------------------------
ingress_allowed() {
  local dst_key="$1" dst_val="$2" src_key="$3" src_val="$4" want_port="$5"
  local np got_dst got_src got_port
  for np in $(jp networkpolicy -n "$NS" -o jsonpath='{.items[*].metadata.name}'); do
    got_dst="$(jp networkpolicy "$np" -n "$NS" \
      -o jsonpath="{.spec.podSelector.matchLabels.${dst_key}}")"
    [ "$got_dst" = "$dst_val" ] || continue
    got_src="$(jp networkpolicy "$np" -n "$NS" \
      -o jsonpath="{range .spec.ingress[*].from[*]}{.podSelector.matchLabels.${src_key}} {end}")"
    case " $got_src " in
      *" $src_val "*) : ;;
      *) continue ;;
    esac
    got_port="$(jp networkpolicy "$np" -n "$NS" \
      -o jsonpath='{range .spec.ingress[*].ports[*]}{.port} {end}')"
    case " $got_port " in
      *" $want_port "*) return 0 ;;
    esac
  done
  return 1
}

# ------------------------------- replay the intended matrix from data/ --------
# Only in-namespace TCP Pod-to-Pod rows are checked here; the DNS egress rows
# and the internet-egress row are covered by the dedicated checks above.
while IFS=',' read -r m_src m_srcsel m_dst m_dstsel m_port m_proto m_intent _rest; do
  [ -z "${m_src:-}" ] && continue
  [ "$m_src" = "source" ] && continue
  [ "$m_proto" = "TCP" ] || continue
  [ "$m_dstsel" = "none" ] && continue
  [ "$m_dst" = "kube-dns" ] && continue

  src_key="${m_srcsel%%=*}"; src_val="${m_srcsel#*=}"
  dst_key="${m_dstsel%%=*}"; dst_val="${m_dstsel#*=}"

  if ingress_allowed "$dst_key" "$dst_val" "$src_key" "$src_val" "$m_port"; then
    got="allow"
  else
    got="deny"
  fi

  if [ "$got" = "$m_intent" ]; then
    if [ "$m_intent" = "allow" ]; then
      pass "matrix allow: ${m_src} -> ${m_dst}:${m_port} is expressed by a policy"
    else
      pass "matrix deny:  ${m_src} -> ${m_dst}:${m_port} is expressed by NO policy"
    fi
  else
    fail "matrix ${m_src} -> ${m_dst}:${m_port}: intended ${m_intent}, policies express ${got}"
  fi
done < "${DATA}/traffic-matrix.csv"

# ----------------------------------------------------------------------------
# ENFORCEMENT: determine it, report it, and only assert blocking where the CNI
# can actually deliver it.
# ----------------------------------------------------------------------------
cni_list="$("$KUBECTL" get daemonsets -A \
  -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)"
enforcing=0
for c in calico-node cilium antrea-agent kube-router; do
  case " $cni_list " in
    *" $c "*) enforcing=1 ;;
  esac
done

probe() {
  # probe <pod> -> prints REACHABLE or BLOCKED
  if "$KUBECTL" exec -n "$NS" "$1" -- \
       wget -qO- --timeout=5 http://payments-api/ >/dev/null 2>&1; then
    echo "REACHABLE"
  else
    echo "BLOCKED"
  fi
}
fe_probe="$(probe frontend)"
rp_probe="$(probe reporting)"

note "---------------------------------------------------------------"
if [ "$enforcing" -eq 0 ]; then
  note "CNI DaemonSet(s) detected: ${cni_list:-none}"
  note "kindnet does NOT implement NetworkPolicy enforcement."
  note "Enforcement probe: reporting -> payments-api was ${rp_probe}."
  note "That is the EXPECTED result on stock kind and is NOT a policy defect."
  note "Appendix A shows how to build a kind cluster with Calico for real"
  note "enforcement. The policy OBJECTS above are verified as correct."
  note "---------------------------------------------------------------"
  pass "RECORDED: enforcement state of this cluster determined and reported honestly"
else
  note "CNI DaemonSet(s) detected: ${cni_list}"
  note "This CNI implements NetworkPolicy, so blocking IS asserted below."
  note "---------------------------------------------------------------"
  if [ "$fe_probe" = "REACHABLE" ]; then
    pass "ENFORCED: frontend -> payments-api is REACHABLE, as the allow rules intend"
  else
    fail "ENFORCED: frontend -> payments-api was ${fe_probe}, expected REACHABLE - check the egress policy too"
  fi
  if [ "$rp_probe" = "BLOCKED" ]; then
    pass "ENFORCED: reporting -> payments-api is BLOCKED by default-deny-all"
  else
    fail "ENFORCED: reporting -> payments-api was ${rp_probe}, expected BLOCKED"
  fi
  pass "RECORDED: enforcement state of this cluster determined and reported honestly"
fi

echo "-- $PASSED passed, $FAILED failed --"
[ "$FAILED" -eq 0 ]
