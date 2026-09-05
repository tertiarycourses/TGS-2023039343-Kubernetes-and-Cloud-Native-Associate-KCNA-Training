#!/usr/bin/env bash
# Lab 05 — Container Images, OCI and the Runtime Interface
# Verification script. Creates nothing; scoped to namespace kcna-lab05.
set -uo pipefail

NS="kcna-lab05"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${LAB_DIR}/data"
PASS=0
FAIL=0

ok()    { printf '  [PASS] %s\n' "$1"; PASS=$((PASS+1)); }
bad()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
skip()  { printf '  [SKIP] %s\n' "$1"; }
head1() { printf '\n== %s\n' "$1"; }

head1 "0. Cluster reachability"
if kubectl version -o json >/dev/null 2>&1; then
  ok "kubectl can reach the API server"
else
  bad "kubectl cannot reach the API server"
  echo; echo "Result: ${PASS} passed, ${FAIL} failed"; exit 1
fi

head1 "1. Namespace and catalog ConfigMap built from data/"
if kubectl get namespace "${NS}" >/dev/null 2>&1; then
  ok "namespace ${NS} exists"
else
  bad "namespace ${NS} is missing"
fi
CM_KEYS="$(kubectl -n "${NS}" get configmap image-catalog \
  -o go-template='{{range $k,$v := .data}}{{$k}} {{end}}' 2>/dev/null)"
case " ${CM_KEYS}" in
  *" image-inventory.csv "*) ok "ConfigMap image-catalog carries image-inventory.csv" ;;
  *) bad "ConfigMap image-catalog is missing key image-inventory.csv" ;;
esac
case " ${CM_KEYS}" in
  *" reference-forms.tsv "*) ok "ConfigMap image-catalog carries reference-forms.tsv" ;;
  *) bad "ConfigMap image-catalog is missing key reference-forms.tsv" ;;
esac

head1 "2. The runtime this node actually uses (CRI)"
RUNTIME="$(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.containerRuntimeVersion}' 2>/dev/null)"
case "${RUNTIME}" in
  containerd://*|cri-o://*)
    ok "node reports a CRI runtime: ${RUNTIME}" ;;
  "")
    bad "could not read status.nodeInfo.containerRuntimeVersion" ;;
  *)
    ok "node reports runtime '${RUNTIME}' (non-standard prefix, but present)" ;;
esac

head1 "3. Tag-pinned catalog Pod"
READY="$(kubectl -n "${NS}" get pod image-catalog \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)"
if [ "${READY}" = "True" ]; then
  ok "Pod image-catalog is Ready"
else
  bad "Pod image-catalog is not Ready"
fi

SPEC_IMG="$(kubectl -n "${NS}" get pod image-catalog \
  -o jsonpath='{.spec.containers[0].image}' 2>/dev/null)"
if [ "${SPEC_IMG}" = "nginx:1.27-alpine" ]; then
  ok "spec.containers[0].image is the TAG you asked for (${SPEC_IMG})"
else
  bad "spec image is '${SPEC_IMG:-<absent>}' (expected nginx:1.27-alpine)"
fi

IMAGE_ID="$(kubectl -n "${NS}" get pod image-catalog \
  -o jsonpath='{.status.containerStatuses[0].imageID}' 2>/dev/null)"
case "${IMAGE_ID}" in
  *@sha256:*)
    ok "status.imageID resolved to a content-addressed digest"
    ;;
  "")
    bad "status.imageID is empty — is the container running?" ;;
  *)
    bad "status.imageID '${IMAGE_ID}' does not contain a sha256 digest" ;;
esac

DIGEST="${IMAGE_ID##*@}"
if [ "${#DIGEST}" -eq 71 ]; then
  ok "digest is a well-formed sha256:<64 hex> string"
else
  bad "digest '${DIGEST}' is ${#DIGEST} characters, expected 71"
fi

head1 "4. The dataset is really being served"
if kubectl -n "${NS}" exec image-catalog -c web -- \
     wget -qO- http://127.0.0.1/image-inventory.csv 2>/dev/null | grep -q 'depot-sandbox'; then
  ok "GET /image-inventory.csv returns the Meridian inventory"
else
  bad "GET /image-inventory.csv did not return the inventory"
fi
if kubectl -n "${NS}" exec image-catalog -c web -- \
     wget -qO- http://127.0.0.1/reference-forms.tsv 2>/dev/null | grep -q 'docker.io/library/nginx:latest'; then
  ok "GET /reference-forms.tsv returns the reference normalisation card"
else
  bad "GET /reference-forms.tsv did not return the reference card"
fi

head1 "5. Governance: running images vs the approved inventory"
# The reference workload MUST be on the approved list.
if grep -q '^depot-web,nginx:1.27-alpine,' "${DATA_DIR}/image-inventory.csv" 2>/dev/null \
   && [ "${SPEC_IMG}" = "nginx:1.27-alpine" ]; then
  ok "image-catalog runs an image listed in data/image-inventory.csv"
else
  bad "image-catalog's image is not the approved depot-web entry"
fi
# The pp-never image is deliberately NOT approved — it models the drift an
# admission policy (Lab 14) would later reject.
PP_NEVER_IMG="$(kubectl -n "${NS}" get pod pp-never \
  -o jsonpath='{.spec.containers[0].image}' 2>/dev/null)"
if [ -n "${PP_NEVER_IMG}" ] \
   && ! grep -q "${PP_NEVER_IMG%%:*}" "${DATA_DIR}/image-inventory.csv" 2>/dev/null; then
  ok "pp-never runs an unapproved image (${PP_NEVER_IMG}) — drift is detectable from data/"
else
  bad "expected pp-never to reference an image absent from the inventory"
fi

head1 "6. imagePullPolicy matrix"
for p in pp-always:Always pp-ifnotpresent:IfNotPresent pp-never:Never; do
  pod="${p%%:*}"; want="${p##*:}"
  got="$(kubectl -n "${NS}" get pod "${pod}" \
    -o jsonpath='{.spec.containers[0].imagePullPolicy}' 2>/dev/null)"
  if [ "${got}" = "${want}" ]; then
    ok "${pod} declares imagePullPolicy: ${want}"
  else
    bad "${pod} imagePullPolicy is '${got:-<absent>}' (expected ${want})"
  fi
done

NEVER_REASON="$(kubectl -n "${NS}" get pod pp-never \
  -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null)"
if [ "${NEVER_REASON}" = "ErrImageNeverPull" ]; then
  ok "pp-never is ErrImageNeverPull — the kubelet never contacted a registry"
else
  bad "pp-never waiting reason is '${NEVER_REASON:-<none>}' (expected ErrImageNeverPull)"
fi

head1 "7. Digest-pinned Pod"
if kubectl -n "${NS}" get pod depot-web-locked >/dev/null 2>&1; then
  LOCK_IMG="$(kubectl -n "${NS}" get pod depot-web-locked \
    -o jsonpath='{.spec.containers[0].image}' 2>/dev/null)"
  LOCK_READY="$(kubectl -n "${NS}" get pod depot-web-locked \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)"
  LOCK_REASON="$(kubectl -n "${NS}" get pod depot-web-locked \
    -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null)"
  case "${LOCK_IMG}" in
    *@sha256:*) ok "depot-web-locked is pinned by digest, not by tag" ;;
    *) bad "depot-web-locked image '${LOCK_IMG}' is not a digest reference" ;;
  esac
  if [ "${LOCK_READY}" = "True" ]; then
    ok "depot-web-locked is Ready — you substituted a digest this cluster can resolve"
    if [ "${LOCK_IMG#*@}" = "${DIGEST}" ]; then
      ok "the repaired digest matches image-catalog's resolved digest exactly"
    else
      bad "repaired digest does not match image-catalog's digest (${DIGEST})"
    fi
  elif [ "${LOCK_REASON}" = "ImagePullBackOff" ] || [ "${LOCK_REASON}" = "ErrImagePull" ]; then
    skip "depot-web-locked is still ${LOCK_REASON} — you are mid-way through section 6"
  else
    bad "depot-web-locked is neither Ready nor in an image-pull error state"
  fi
else
  skip "depot-web-locked not present"
fi

echo
echo "Result: ${PASS} passed, ${FAIL} failed"
[ "${FAIL}" -eq 0 ]
