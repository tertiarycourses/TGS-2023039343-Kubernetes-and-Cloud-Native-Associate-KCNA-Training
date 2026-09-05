#!/usr/bin/env bash
# Lab 14 — Namespaces, ServiceAccounts and RBAC
#
# The permission assertions are driven entirely by data/rbac-matrix.csv, using
# `kubectl auth can-i --as=system:serviceaccount:<ns>:<sa>` as the oracle.
# Read-only: the script creates and deletes nothing.
#
# Requires that YOUR kubeconfig user may impersonate (cluster-admin on kind).
#
# Usage:  bash verification/checks.sh
# Env:    KUBECTL (default "kubectl"), NS (default "kcna-lab14")

set -uo pipefail

KUBECTL="${KUBECTL:-kubectl}"
NS="${NS:-kcna-lab14}"
CR="kcna-lab14-configmap-viewer"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB="$(cd "${HERE}/.." && pwd)"
DATA="${LAB}/data"

PASSED=0
FAILED=0
pass() { printf 'PASS  %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }

echo "== Lab 14 verification: Namespaces, ServiceAccounts and RBAC =="

if "$KUBECTL" get namespace "$NS" >/dev/null 2>&1; then
  pass "namespace $NS exists"
else
  fail "namespace $NS exists"
  echo "-- $PASSED passed, $FAILED failed --"
  exit 1
fi

psa="$("$KUBECTL" get namespace "$NS" \
  -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null)"
if [ "$psa" = "baseline" ]; then
  pass "namespace enforces the baseline Pod Security profile"
else
  fail "namespace enforces the baseline Pod Security profile (got '${psa}')"
fi

sa_ok=1
for sa in ops-reader deploy-bot; do
  "$KUBECTL" get serviceaccount "$sa" -n "$NS" >/dev/null 2>&1 || sa_ok=0
done
if [ "$sa_ok" -eq 1 ]; then
  pass "ServiceAccounts ops-reader and deploy-bot exist"
else
  fail "ServiceAccounts ops-reader and deploy-bot exist"
fi

# ------------------------------------------- the Role really is read-only -----
role_verbs="$("$KUBECTL" get role pod-reader -n "$NS" \
  -o jsonpath='{range .rules[*]}{range .verbs[*]}{@}{"\n"}{end}{end}' 2>/dev/null | sort -u | tr '\n' ' ')"
if [ -n "$role_verbs" ] && ! printf '%s' "$role_verbs" \
    | grep -qE '(^| )(create|update|patch|delete|deletecollection|\*)( |$)'; then
  pass "Role pod-reader is read-only (no create/update/patch/delete verbs)"
else
  fail "Role pod-reader is read-only - verbs found: '${role_verbs}'"
fi

rb_kind="$("$KUBECTL" get rolebinding ops-reader-can-read-pods -n "$NS" \
  -o jsonpath='{.roleRef.kind}/{.roleRef.name}:{.subjects[0].kind}/{.subjects[0].name}' 2>/dev/null)"
if [ "$rb_kind" = "Role/pod-reader:ServiceAccount/ops-reader" ]; then
  pass "RoleBinding ops-reader-can-read-pods binds Role/pod-reader to ops-reader"
else
  fail "RoleBinding ops-reader-can-read-pods binds Role/pod-reader to ops-reader (got '${rb_kind}')"
fi

# ------------------- the ClusterRole is read-only, narrow and NOT cluster-bound
cr_verbs="$("$KUBECTL" get clusterrole "$CR" \
  -o jsonpath='{range .rules[*]}{range .verbs[*]}{@}{"\n"}{end}{end}' 2>/dev/null | sort -u | tr '\n' ' ')"
cr_res="$("$KUBECTL" get clusterrole "$CR" \
  -o jsonpath='{range .rules[*]}{range .resources[*]}{@}{"\n"}{end}{end}' 2>/dev/null | sort -u | tr '\n' ' ')"
if [ -n "$cr_verbs" ] \
   && ! printf '%s' "$cr_verbs" | grep -qE '(^| )(create|update|patch|delete|deletecollection|escalate|bind|impersonate|\*)( |$)' \
   && ! printf '%s' "$cr_res" | grep -q '\*'; then
  pass "ClusterRole ${CR} is read-only with no wildcards"
else
  fail "ClusterRole ${CR} is read-only with no wildcards (verbs='${cr_verbs}' resources='${cr_res}')"
fi

crb="$("$KUBECTL" get clusterrolebindings \
  -o jsonpath="{range .items[?(@.roleRef.name==\"${CR}\")]}{.metadata.name}{\"\n\"}{end}" 2>/dev/null)"
if [ -z "$crb" ]; then
  pass "NO ClusterRoleBinding references ${CR} (grant stays namespaced)"
else
  fail "a ClusterRoleBinding references ${CR}: '${crb}' - this would widen the grant cluster-wide"
fi

# --------------------------- the permission matrix, straight from data/ -------
while IFS=',' read -r m_sa m_verb m_res m_ns m_expect _rest; do
  [ -z "${m_sa:-}" ] && continue
  [ "$m_sa" = "serviceaccount" ] && continue
  subject="system:serviceaccount:${NS}:${m_sa}"
  if "$KUBECTL" auth can-i "$m_verb" "$m_res" \
       --as="$subject" -n "$m_ns" >/dev/null 2>&1; then
    got="yes"
  else
    got="no"
  fi
  if [ "$got" = "$m_expect" ]; then
    pass "can-i ${m_verb} ${m_res} as ${m_sa} in ${m_ns} = ${m_expect}"
  else
    fail "can-i ${m_verb} ${m_res} as ${m_sa} in ${m_ns}: expected ${m_expect}, got ${got}"
  fi
done < "${DATA}/rbac-matrix.csv"

# ------------------------------------------------ projected token behaviour --
tok_path="$("$KUBECTL" get pod token-inspector -n "$NS" \
  -o jsonpath='{.spec.volumes[*].projected.sources[*].serviceAccountToken.path}' 2>/dev/null)"
if [ "$tok_path" = "token" ]; then
  pass "token-inspector has a projected serviceAccountToken volume"
else
  fail "token-inspector has a projected serviceAccountToken volume (got '${tok_path}')"
fi

in_ns="$("$KUBECTL" exec -n "$NS" token-inspector -- \
  cat /var/run/secrets/kubernetes.io/serviceaccount/namespace 2>/dev/null)"
if [ "$in_ns" = "$NS" ]; then
  pass "token-inspector namespace file contains ${NS}"
else
  fail "token-inspector namespace file contains ${NS} (got '${in_ns}')"
fi

nt_automount="$("$KUBECTL" get pod no-token -n "$NS" \
  -o jsonpath='{.spec.automountServiceAccountToken}' 2>/dev/null)"
nt_vols="$("$KUBECTL" get pod no-token -n "$NS" \
  -o jsonpath='{.spec.volumes}' 2>/dev/null)"
if [ "$nt_automount" = "false" ] && [ -z "$nt_vols" ]; then
  pass "no-token Pod has no ServiceAccount volume mounted"
else
  fail "no-token Pod has no ServiceAccount volume mounted (automount='${nt_automount}' volumes='${nt_vols}')"
fi

echo "-- $PASSED passed, $FAILED failed --"
[ "$FAILED" -eq 0 ]
