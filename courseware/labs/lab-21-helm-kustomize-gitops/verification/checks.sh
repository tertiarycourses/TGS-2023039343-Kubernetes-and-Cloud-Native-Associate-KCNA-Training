#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Lab 21 — Packaging and Delivery: Helm, Kustomize and GitOps
#
# GRADING MODEL: this lab is graded on the STATIC RENDER, not on a cluster
# install. `kubectl kustomize` is built into kubectl and always works offline,
# so every graded check below runs with NO CLUSTER and NO NETWORK.
#
# helm is OPTIONAL. If `helm` is on PATH the script additionally lints and
# renders the chart and grades that too; if not, those checks report [SKIP]
# and do not count as failures. Install pointer:
#     https://helm.sh/docs/intro/install/
#     macOS:  brew install helm
#     Linux:  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
#
# The cluster-state checks at the end are also optional and are skipped when
# no cluster is reachable.
#
#   usage:  bash verification/checks.sh
#   env:    KUBECTL=/path/to/kubectl   HELM=/path/to/helm   NS=kcna-lab21
# ---------------------------------------------------------------------------
set -uo pipefail

KUBECTL="${KUBECTL:-kubectl}"
HELM="${HELM:-helm}"
NS="${NS:-kcna-lab21}"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INVENTORY="$LAB_DIR/data/release-inventory.csv"

PASS=0
FAIL=0
SKIP=0
pass() { printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }
skip() { printf '[SKIP] %s\n' "$1"; SKIP=$((SKIP + 1)); }
check() { if [ "$1" = "0" ]; then pass "$2"; else fail "$2"; fi; }

printf '== Lab 21 verification — static render (no cluster required) ==\n'

if ! command -v "$KUBECTL" >/dev/null 2>&1; then
  printf '[FAIL] kubectl not found on PATH (set KUBECTL=/path/to/kubectl)\n'
  exit 2
fi

# ---------------------------------------------------------------------------
# Section 1 — chart structure (static, no helm needed)
# ---------------------------------------------------------------------------
MISSING=""
for f in Chart.yaml values.yaml .helmignore \
         templates/_helpers.tpl templates/deployment.yaml \
         templates/service.yaml templates/configmap.yaml templates/NOTES.txt; do
  [ -f "$LAB_DIR/chart/$f" ] || MISSING="$MISSING $f"
done
if [ -z "$MISSING" ]; then
  pass "chart/ contains Chart.yaml, values.yaml, _helpers.tpl and 3 templates"
else
  fail "chart/ is missing:$MISSING"
fi

if grep -q '^apiVersion: v2' "$LAB_DIR/chart/Chart.yaml" 2>/dev/null \
   && grep -q '^name: tracklane' "$LAB_DIR/chart/Chart.yaml" 2>/dev/null \
   && grep -qE '^version: [0-9]+\.[0-9]+\.[0-9]+' "$LAB_DIR/chart/Chart.yaml" 2>/dev/null; then
  pass "Chart.yaml declares apiVersion v2, name tracklane and a semver version"
else
  fail "Chart.yaml must declare apiVersion: v2, name: tracklane and a semver version"
fi

# Pinned tags only. Looks at actual image references and tag fields, not at
# prose — chart/templates/_helpers.tpl legitimately contains the string
# "latest" inside the guard that REJECTS it.
LATEST_HITS="$( {
  grep -rhE '^[[:space:]]*image:[[:space:]]*[^[:space:]]+:latest[[:space:]]*$' \
    "$LAB_DIR/chart" "$LAB_DIR/kustomize" "$LAB_DIR/manifests" 2>/dev/null
  grep -rhE '^[[:space:]]*(tag|newTag):[[:space:]]*"?latest"?[[:space:]]*$' \
    "$LAB_DIR/chart" "$LAB_DIR/kustomize" "$LAB_DIR/manifests" 2>/dev/null
} | grep -c '.' || true)"
if [ "${LATEST_HITS:-0}" = "0" ]; then
  pass "no ':latest' image tag anywhere in chart/, kustomize/ or manifests/"
else
  fail "found ${LATEST_HITS} unpinned ':latest' image reference(s)"
fi

# ---------------------------------------------------------------------------
# Section 2 — Kustomize static render. THIS IS THE GRADED CORE.
# ---------------------------------------------------------------------------
DEV_OUT="$("$KUBECTL" kustomize "$LAB_DIR/kustomize/overlays/dev" 2>/dev/null)"
check $? "kubectl kustomize renders overlays/dev"

PROD_OUT="$("$KUBECTL" kustomize "$LAB_DIR/kustomize/overlays/prod" 2>/dev/null)"
check $? "kubectl kustomize renders overlays/prod"

if [ -z "$DEV_OUT" ] || [ -z "$PROD_OUT" ]; then
  printf -- '------------------------------------------------\n'
  printf '%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
  printf 'Kustomize render failed; fix that before the remaining checks.\n'
  exit 1
fi

# Both renders must be valid, applyable YAML.
printf '%s' "$DEV_OUT"  | "$KUBECTL" apply --dry-run=client -f - >/dev/null 2>&1
DEV_DRY=$?
printf '%s' "$PROD_OUT" | "$KUBECTL" apply --dry-run=client -f - >/dev/null 2>&1
PROD_DRY=$?
if [ "$DEV_DRY" = "0" ] && [ "$PROD_DRY" = "0" ]; then
  pass "both rendered overlays pass kubectl apply --dry-run=client"
else
  skip "kubectl apply --dry-run=client needs a reachable cluster for discovery"
fi

# --- the dataset in data/release-inventory.csv drives these assertions -----
render_for() {
  case "$1" in
    dev)  printf '%s' "$DEV_OUT" ;;
    prod) printf '%s' "$PROD_OUT" ;;
  esac
}

INV_ROWS=0
INV_OK=0
while IFS=, read -r ENVN SUFFIX REPLICAS CPU MEM LANES LOGLVL FEAT; do
  [ "$ENVN" = "environment" ] && continue
  [ -z "$ENVN" ] && continue
  INV_ROWS=$((INV_ROWS + 1))
  OUT="$(render_for "$ENVN")"

  # name suffix
  printf '%s' "$OUT" | grep -q "name: tracklane${SUFFIX}$" \
    || { fail "overlays/${ENVN}: expected an object named tracklane${SUFFIX}"; INV_OK=1; continue; }
  # replicas
  printf '%s' "$OUT" | grep -q "^  replicas: ${REPLICAS}$" \
    || { fail "overlays/${ENVN}: expected replicas: ${REPLICAS}"; INV_OK=1; continue; }
  # resource requests
  printf '%s' "$OUT" | grep -q "cpu: ${CPU}$" \
    || { fail "overlays/${ENVN}: expected cpu request ${CPU}"; INV_OK=1; continue; }
  printf '%s' "$OUT" | grep -q "memory: ${MEM}$" \
    || { fail "overlays/${ENVN}: expected memory request ${MEM}"; INV_OK=1; continue; }
  # config literals
  printf '%s' "$OUT" | grep -q "LOG_LEVEL: ${LOGLVL}$" \
    || { fail "overlays/${ENVN}: expected LOG_LEVEL: ${LOGLVL}"; INV_OK=1; continue; }
  printf '%s' "$OUT" | grep -q "FEATURE_LANE_ETA: \"${FEAT}\"$" \
    || { fail "overlays/${ENVN}: expected FEATURE_LANE_ETA: \"${FEAT}\""; INV_OK=1; continue; }
  # lane dataset row count (CSV data rows embedded in the generated ConfigMap)
  GOT_LANES="$(printf '%s' "$OUT" | grep -c '^    SG-' || true)"
  [ "${GOT_LANES:-0}" = "$LANES" ] \
    || { fail "overlays/${ENVN}: expected ${LANES} lane rows, rendered ${GOT_LANES:-0}"; INV_OK=1; continue; }

  pass "overlays/${ENVN} matches data/release-inventory.csv (suffix ${SUFFIX}, ${REPLICAS} replicas, ${CPU}/${MEM}, ${LANES} lanes, LOG_LEVEL=${LOGLVL})"
done < "$INVENTORY"

if [ "$INV_ROWS" -lt 2 ]; then
  fail "data/release-inventory.csv should describe at least 2 environments (saw $INV_ROWS)"
fi

# --- transformer behaviour -------------------------------------------------
DEV_SEL="$(printf '%s' "$DEV_OUT"  | grep -c 'app.kubernetes.io/instance: tracklane-dev'  || true)"
PROD_SEL="$(printf '%s' "$PROD_OUT" | grep -c 'app.kubernetes.io/instance: tracklane-prod' || true)"
if [ "${DEV_SEL:-0}" -ge 4 ] && [ "${PROD_SEL:-0}" -ge 4 ]; then
  pass "the instance label was injected into selectors as well as metadata (includeSelectors: true)"
else
  fail "instance label should appear in metadata AND selectors in both overlays (dev=${DEV_SEL}, prod=${PROD_SEL})"
fi

printf '%s' "$PROD_OUT" | grep -q 'image: docker.io/library/nginx:1.27-alpine'
check $? "the prod images transformer rewrote the image to a fully-qualified registry path"

printf '%s' "$DEV_OUT" | grep -q 'image: nginx:1.27-alpine'
check $? "dev inherited the base image reference unchanged"

# JSON 6902 patch applied in prod only
if printf '%s' "$PROD_OUT" | grep -q 'periodSeconds: 10' \
   && printf '%s' "$DEV_OUT" | grep -q 'periodSeconds: 5'; then
  pass "the prod JSON 6902 patch changed readinessProbe.periodSeconds 5 -> 10"
else
  fail "expected readinessProbe.periodSeconds 5 in dev and 10 in prod"
fi

# Generator hash suffixes are on, and the reference was rewritten
DEV_CM="$(printf '%s' "$DEV_OUT" | sed -n 's/^  name: \(tracklane-config-dev-[a-z0-9]\{5,\}\)$/\1/p' | head -1)"
if [ -n "$DEV_CM" ] && printf '%s' "$DEV_OUT" | grep -q "name: ${DEV_CM}$"; then
  pass "generated ConfigMap carries a content hash (${DEV_CM}) and the Deployment reference was rewritten"
else
  fail "expected a hash-suffixed tracklane-config-dev-* ConfigMap referenced from the Deployment"
fi

# The two overlays must genuinely differ
if [ "$DEV_OUT" = "$PROD_OUT" ]; then
  fail "overlays/dev and overlays/prod rendered identically — the overlays are not doing anything"
else
  pass "overlays/dev and overlays/prod render materially different output"
fi

# ---------------------------------------------------------------------------
# Section 3 — Helm (optional)
# ---------------------------------------------------------------------------
if command -v "$HELM" >/dev/null 2>&1; then
  "$HELM" lint "$LAB_DIR/chart" >/dev/null 2>&1
  check $? "helm lint passes on chart/"

  H_DEV="$("$HELM" template tracklane-dev "$LAB_DIR/chart" \
    --namespace "$NS" \
    -f "$LAB_DIR/data/values-dev.yaml" \
    --set-file lanes.csv="$LAB_DIR/data/shipping-lanes.csv" 2>/dev/null)"
  check $? "helm template renders the chart with data/values-dev.yaml"

  H_PROD="$("$HELM" template tracklane-prod "$LAB_DIR/chart" \
    --namespace "$NS" \
    -f "$LAB_DIR/data/values-prod.yaml" \
    --set-file lanes.csv="$LAB_DIR/data/shipping-lanes.csv" 2>/dev/null)"
  check $? "helm template renders the chart with data/values-prod.yaml"

  if printf '%s' "$H_DEV" | grep -q '^  replicas: 1$' \
     && printf '%s' "$H_PROD" | grep -q '^  replicas: 3$'; then
    pass "the values files drove replicaCount 1 (dev) and 3 (prod)"
  else
    fail "expected replicas 1 from values-dev.yaml and 3 from values-prod.yaml"
  fi

  if ! printf '%s' "$H_DEV" | grep -q 'kind: PodDisruptionBudget' \
     && printf '%s' "$H_PROD" | grep -q 'kind: PodDisruptionBudget'; then
    pass "the conditional PodDisruptionBudget renders in prod only"
  else
    fail "PodDisruptionBudget should render for prod and NOT for dev"
  fi

  printf '%s' "$H_DEV" | grep -q 'checksum/config:'
  check $? "the Deployment carries a checksum/config annotation"

  # The dataset must have travelled from data/ into the render.
  H_LANES="$(printf '%s' "$H_PROD" | grep -c '^    SG-' || true)"
  D_LANES=$(( $(grep -c '' "$LAB_DIR/data/shipping-lanes.csv") - 1 ))
  if [ "${H_LANES:-0}" = "$D_LANES" ]; then
    pass "--set-file carried all ${D_LANES} rows of data/shipping-lanes.csv into the render"
  else
    fail "expected ${D_LANES} lane rows in the helm render (saw ${H_LANES:-0})"
  fi
else
  skip "helm not installed — chart render checks skipped (see https://helm.sh/docs/intro/install/)"
  skip "helm not installed — values-file diff checks skipped"
  skip "helm not installed — conditional PodDisruptionBudget check skipped"
  skip "helm not installed — checksum/config annotation check skipped"
  skip "helm not installed — --set-file dataset check skipped"
fi

# ---------------------------------------------------------------------------
# Section 4 — GitOps manifests are readable and kept out of manifests/
# ---------------------------------------------------------------------------
if [ -f "$LAB_DIR/gitops/argocd-application.yaml" ] \
   && ! ls "$LAB_DIR/manifests"/*argocd* >/dev/null 2>&1; then
  pass "the Argo CD Application lives in gitops/, not manifests/ (it needs a CRD)"
else
  fail "gitops/argocd-application.yaml must exist and must NOT be in manifests/"
fi

ARGO="$LAB_DIR/gitops/argocd-application.yaml"
if grep -q 'prune: true' "$ARGO" && grep -q 'selfHeal: true' "$ARGO" \
   && grep -q 'repoURL:' "$ARGO" && grep -q 'targetRevision:' "$ARGO"; then
  pass "the Application declares repoURL, targetRevision, prune and selfHeal"
else
  fail "the Application must declare repoURL, targetRevision, prune: true and selfHeal: true"
fi

# ---------------------------------------------------------------------------
# Section 5 — cluster state (OPTIONAL: only if a cluster is reachable)
# ---------------------------------------------------------------------------
if "$KUBECTL" get namespace "$NS" >/dev/null 2>&1; then
  D_AVAIL="$("$KUBECTL" -n "$NS" get deployment tracklane-dev \
    -o jsonpath='{.status.availableReplicas}' 2>/dev/null)"
  if [ "${D_AVAIL:-0}" -ge 1 ] 2>/dev/null; then
    pass "deployment/tracklane-dev is available in $NS (applied from the dev overlay)"
  else
    fail "deployment/tracklane-dev should be available in $NS after Step 7"
  fi

  PRIV="$("$KUBECTL" -n "$NS" get pods \
    -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.securityContext.privileged}{"\n"}{end}{end}' 2>/dev/null \
    | grep -c '^true$' || true)"
  if [ "${PRIV:-0}" = "0" ]; then
    pass "no container in $NS requests privileged: true"
  else
    fail "$PRIV privileged container(s) found in $NS — this lab must not need any"
  fi
else
  skip "namespace $NS not present — cluster-state checks skipped (static grading still applies)"
  skip "namespace $NS not present — privileged-container check skipped"
fi

printf -- '------------------------------------------------\n'
printf '%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
