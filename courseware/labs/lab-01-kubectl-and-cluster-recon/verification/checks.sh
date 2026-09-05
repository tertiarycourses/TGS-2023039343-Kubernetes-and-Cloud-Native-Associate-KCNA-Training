#!/usr/bin/env bash
# Lab 01 — Cluster Reconnaissance with kubectl
# Verification script. Read-only apart from nothing: it creates and deletes no
# objects. Scoped entirely to the namespace kcna-lab01.
set -uo pipefail

NS="kcna-lab01"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${LAB_DIR}/data"
PASS=0
FAIL=0

ok()   { printf '  [PASS] %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
head1() { printf '\n== %s\n' "$1"; }

head1 "0. kubectl and cluster reachability"
if kubectl version -o json >/dev/null 2>&1; then
  ok "kubectl can reach the API server"
else
  bad "kubectl cannot reach the API server — check your kubeconfig/context"
  echo; echo "Result: ${PASS} passed, ${FAIL} failed"; exit 1
fi

head1 "1. Namespace and namespaced policy objects"
if kubectl get namespace "${NS}" >/dev/null 2>&1; then
  ok "namespace ${NS} exists"
else
  bad "namespace ${NS} is missing — apply manifests/00-namespace.yaml"
fi

if kubectl -n "${NS}" get resourcequota depot-recon-quota >/dev/null 2>&1; then
  ok "ResourceQuota depot-recon-quota exists"
else
  bad "ResourceQuota depot-recon-quota is missing"
fi

if kubectl -n "${NS}" get limitrange depot-recon-defaults >/dev/null 2>&1; then
  ok "LimitRange depot-recon-defaults exists"
else
  bad "LimitRange depot-recon-defaults is missing"
fi

head1 "2. ConfigMap built from data/recon-checklist.csv"
if kubectl -n "${NS}" get configmap recon-checklist >/dev/null 2>&1; then
  ok "ConfigMap recon-checklist exists"
  KEYS="$(kubectl -n "${NS}" get configmap recon-checklist -o jsonpath='{.data}' 2>/dev/null)"
  case "${KEYS}" in
    *recon-checklist.csv*) ok "ConfigMap carries key recon-checklist.csv" ;;
    *) bad "ConfigMap has no recon-checklist.csv key (use --from-file on the data/ path)" ;;
  esac
  case "${KEYS}" in
    *RC-010*) ok "ConfigMap content includes checklist row RC-010" ;;
    *) bad "ConfigMap content does not look like the shipped CSV" ;;
  esac
else
  bad "ConfigMap recon-checklist is missing — create it from data/recon-checklist.csv"
fi

head1 "3. recon-shell Pod"
PHASE="$(kubectl -n "${NS}" get pod recon-shell -o jsonpath='{.status.phase}' 2>/dev/null)"
if [ "${PHASE}" = "Running" ]; then
  ok "Pod recon-shell phase is Running"
else
  bad "Pod recon-shell phase is '${PHASE:-<absent>}' (expected Running)"
fi

READY="$(kubectl -n "${NS}" get pod recon-shell \
  -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)"
if [ "${READY}" = "true" ]; then
  ok "container 'shell' reports ready=true"
else
  bad "container 'shell' ready='${READY:-<absent>}'"
fi

POD_LOG="$(kubectl -n "${NS}" logs recon-shell 2>/dev/null)"
if [[ "${POD_LOG}" == *'checklist rows: 13'* ]]; then
  ok "recon-shell logs report 13 lines (CSV header plus 12 checklist records) read from the mounted CSV"
else
  bad "recon-shell logs do not show 'checklist rows: 13' — is the ConfigMap mounted?"
fi

head1 "4. Core API inventory matches data/core-api-inventory.tsv"
if [ ! -f "${DATA_DIR}/core-api-inventory.tsv" ]; then
  bad "baseline file ${DATA_DIR}/core-api-inventory.tsv not found"
else
  LIVE="$(kubectl api-resources --api-group='' --no-headers 2>/dev/null | awk '{print $1}')"
  MISSING=""
  while IFS=$'\t' read -r name _ns _kind; do
    case "${name}" in ''|\#*) continue ;; esac
    if ! printf '%s\n' "${LIVE}" | grep -qx "${name}"; then
      MISSING="${MISSING} ${name}"
    fi
  done < "${DATA_DIR}/core-api-inventory.tsv"
  if [ -z "${MISSING}" ]; then
    ok "all 14 baseline core resources are served by this cluster"
  else
    bad "core resources missing from this cluster:${MISSING}"
  fi
fi

head1 "5. kubectl explain reaches the live OpenAPI schema"
if kubectl explain pod.spec.containers.resources 2>/dev/null | grep -q 'requests'; then
  ok "kubectl explain pod.spec.containers.resources returns the 'requests' field"
else
  bad "kubectl explain did not return the expected schema fields"
fi

head1 "6. Verbose mode exposes the REST call"
TRACE="$(kubectl -n "${NS}" get pods --v=6 2>&1)"
if [[ "${TRACE}" == *"api/v1/namespaces/${NS}/pods"* ]]; then
  ok "--v=6 shows GET .../api/v1/namespaces/${NS}/pods"
else
  bad "--v=6 output did not contain the expected request path"
fi

echo
echo "Result: ${PASS} passed, ${FAIL} failed"
[ "${FAIL}" -eq 0 ]
