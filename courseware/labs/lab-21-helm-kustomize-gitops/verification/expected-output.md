# Lab 21 — expected output

Reference transcript for **Lab 21 · Packaging and Delivery: Helm, Kustomize and GitOps**, namespace `kcna-lab21`.

> **How to read this file.** Pod name suffixes, ages, sha256 checksums and cluster IPs are environment-specific and **will differ**. Object names, replica counts, config values, lane row counts, ConfigMap **hash suffixes**, image references and error strings must match exactly — the generator hashes are deterministic functions of content, so if yours differ, your content differs.
>
> **The graded core of this lab is the static render** and requires neither a cluster nor helm.

---

## Tooling baseline

```
$ helm version
command not found: helm
```

Expected on the authoring machine. Helm is **optional**; see the install pointers in README section "Tooling note".

```
$ kubectl version --client
Client Version: v1.31.0
Kustomize Version: v5.4.2
```

**Required signal:** `Kustomize Version` must be **v5.x**. On v4.x the `labels:` transformer used by both overlays is rejected with `json: unknown field "labels"`.

---

## Step 2 — the "before" state

```
$ kubectl apply -f manifests/01-tracklane-handwritten.yaml
configmap/tracklane-handwritten-config created
service/tracklane-handwritten created
deployment.apps/tracklane-handwritten created

$ grep -c 'tracklane-handwritten' manifests/01-tracklane-handwritten.yaml
11
$ grep -c 'app.kubernetes.io/instance: tracklane-handwritten' manifests/01-tracklane-handwritten.yaml
6
```

**Required signal:** `11` and `6`. These are exact counts against the shipped file; if you edited it they will differ.

---

## Step 3 — chart structure

```
$ find chart -type f | sort
chart/.helmignore
chart/Chart.yaml
chart/templates/NOTES.txt
chart/templates/_helpers.tpl
chart/templates/configmap.yaml
chart/templates/deployment.yaml
chart/templates/service.yaml
chart/values.yaml
```

**Required signal:** all eight files present. `checks.sh` asserts this without helm.

```
$ grep -E '^(version|appVersion|apiVersion|type|kubeVersion):' chart/Chart.yaml
apiVersion: v2
type: application
version: 0.3.0
appVersion: "1.27"
```

```
$ grep -n '^{{- define' chart/templates/_helpers.tpl
14:{{- define "tracklane.name" -}}
24:{{- define "tracklane.fullname" -}}
41:{{- define "tracklane.chart" -}}
52:{{- define "tracklane.selectorLabels" -}}
62:{{- define "tracklane.labels" -}}
76:{{- define "tracklane.validateImage" -}}
```

**Required signal:** six named templates. Line numbers shift if you edit the file.

---

## Step 4 — Helm render (requires helm; SKIP without it)

```
$ helm template tracklane-dev ./chart --namespace kcna-lab21 -f data/values-dev.yaml --set-file lanes.csv=data/shipping-lanes.csv > /tmp/tracklane-dev.yaml
$ grep -E '^kind:' /tmp/tracklane-dev.yaml
kind: ConfigMap
kind: ConfigMap
kind: Service
kind: Deployment
```

```
$ grep -E '^kind:' /tmp/tracklane-prod.yaml
kind: PodDisruptionBudget
kind: ConfigMap
kind: ConfigMap
kind: Service
kind: Deployment
```

**On ordering:** Helm emits manifests in its fixed **install order** (policy objects, then config, then services, then workloads), not in source-file order — which is why `PodDisruptionBudget` leads the prod render despite being written at the bottom of `templates/deployment.yaml`. Grade on the *set* of kinds, not the sequence.

**Required signal:** `PodDisruptionBudget` appears in the **prod** render and **not** in the dev render. That is the conditional-resource capability Kustomize does not have.

The environment diff:

```
$ diff <(grep -E 'replicas:|LOG_LEVEL|FEATURE_LANE_ETA|CACHE_TTL|cpu:|memory:|^kind:' /tmp/tracklane-dev.yaml) \
       <(grep -E 'replicas:|LOG_LEVEL|FEATURE_LANE_ETA|CACHE_TTL|cpu:|memory:|^kind:' /tmp/tracklane-prod.yaml)
<   CACHE_TTL_SECONDS: "5"
<   FEATURE_LANE_ETA: "true"
<   LOG_LEVEL: "debug"
---
>   CACHE_TTL_SECONDS: "300"
>   FEATURE_LANE_ETA: "false"
>   LOG_LEVEL: "warn"
<   replicas: 1
---
>   replicas: 3
> kind: PodDisruptionBudget
```

**Required signal:** every differing line traces to `data/values-dev.yaml` or `data/values-prod.yaml`. Exact diff hunk headers (`2,4c2,4`) vary with grep output length.

Precedence proof:

```
$ helm template tracklane-dev ./chart -f data/values-dev.yaml --set replicaCount=7 | grep -m1 'replicas:'
  replicas: 7
```

`--set` (7) beat the values file (1) which beat the chart default (2).

Dataset proof:

```
$ grep -c '^    SG-' /tmp/tracklane-prod.yaml
9
$ echo "source rows: $(( $(wc -l < data/shipping-lanes.csv) - 1 ))"
source rows: 9
```

**Required signal:** the two numbers are equal.

Checksum annotation:

```
$ grep -A1 'annotations:' /tmp/tracklane-prod.yaml | grep checksum
        checksum/config: 3f7a1e5c9b02d846af1739e5c0d2b68475fa03c91d6e847b25c0af9e1d637208
```

**The hash value will differ** — it is a sha256 of your rendered ConfigMap template. The signal is that the annotation is **present**.

```
$ helm lint ./chart
==> Linting ./chart
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
```

**Required signal:** `0 chart(s) failed`. The `icon is recommended` INFO is expected and harmless.

---

## Step 5 — the base is ordinary YAML

```
$ kubectl apply --dry-run=client -f kustomize/base/deployment.yaml
deployment.apps/tracklane created (dry run)

$ kubeconform -strict -summary kustomize/base/deployment.yaml kustomize/base/service.yaml
Summary: 2 resources found in 2 files - Valid: 2, Invalid: 0, Errors: 0, Skipped: 0
```

**Required signal:** both succeed. Neither is possible against a Helm template, and that is the fundamental trade between the two tools.

---

## Step 6 — both overlays render

```
$ kubectl kustomize kustomize/overlays/dev | grep -E '^kind:|^  name:|^  replicas:|LOG_LEVEL|FEATURE_LANE_ETA'
kind: ConfigMap
  name: tracklane-config-dev-m889h8f92h
  FEATURE_LANE_ETA: "true"
  LOG_LEVEL: debug
kind: ConfigMap
  name: tracklane-lanes-dev-6gmkh6tdbh
kind: Service
  name: tracklane-dev
kind: Deployment
  name: tracklane-dev
  replicas: 1
```

```
$ kubectl kustomize kustomize/overlays/prod | grep -E '^kind:|^  name:|^  replicas:|LOG_LEVEL|FEATURE_LANE_ETA'
kind: ConfigMap
  name: tracklane-config-prod-8c5db4d86b
  FEATURE_LANE_ETA: "false"
  LOG_LEVEL: warn
kind: ConfigMap
  name: tracklane-lanes-prod-t7f75mc2d4
kind: Service
  name: tracklane-prod
kind: Deployment
  name: tracklane-prod
  replicas: 3
```

**Required signal — and the hashes are exact.** Kustomize's generator suffix is a deterministic hash of the ConfigMap's content, so on unmodified lab files you will get precisely `tracklane-config-dev-m889h8f92h`, `tracklane-lanes-dev-6gmkh6tdbh`, `tracklane-config-prod-8c5db4d86b` and `tracklane-lanes-prod-t7f75mc2d4`. **A different hash means your content differs** — that is exactly what makes the mechanism useful.

The full contract:

```
$ for env in dev prod; do ... done
dev   replicas=1 cpu=50m lanes=4 image=nginx:1.27-alpine probe=5
prod  replicas=3 cpu=100m lanes=9 image=docker.io/library/nginx:1.27-alpine probe=10
```

**Required signal:** every value matches `data/release-inventory.csv`. This line is the lab's central result.

Selector isolation:

```
$ for env in dev prod; do ... done
dev selector: app.kubernetes.io/instance:tracklane-dev
prod selector: app.kubernetes.io/instance:tracklane-prod
```

**Required signal:** the two selectors differ. Identical selectors would mean `includeSelectors` was left false and the two environments would silently share Pods.

---

## Step 7 — apply the dev overlay

```
$ kubectl apply -k kustomize/overlays/dev
configmap/tracklane-config-dev-m889h8f92h created
configmap/tracklane-lanes-dev-6gmkh6tdbh created
service/tracklane-dev created
deployment.apps/tracklane-dev created

$ kubectl -n kcna-lab21 rollout status deployment/tracklane-dev --timeout=180s
deployment "tracklane-dev" successfully rolled out
```

```
$ kubectl -n kcna-lab21 exec deployment/tracklane-dev -- sh -c 'echo "LOG_LEVEL=$LOG_LEVEL FEATURE_LANE_ETA=$FEATURE_LANE_ETA"; echo "lanes=$(( $(wc -l < /usr/share/nginx/html/lanes/shipping-lanes.csv) - 1 ))"'
LOG_LEVEL=debug FEATURE_LANE_ETA=true
lanes=4
```

**Required signal:** `debug`, `true`, `4` — the dev contract from `data/release-inventory.csv`, delivered without editing a copy of the base.

Generator-hash rollout:

```
$ kubectl apply -k kustomize/overlays/dev
configmap/tracklane-config-dev-f2c68b9047 created
configmap/tracklane-lanes-dev-6gmkh6tdbh unchanged
service/tracklane-dev unchanged
deployment.apps/tracklane-dev configured

$ kubectl -n kcna-lab21 exec deployment/tracklane-dev -- printenv CACHE_TTL_SECONDS
15
```

**Required signal:** a **new** ConfigMap name and `deployment.apps/tracklane-dev configured`. If the Deployment reported `unchanged`, the hash suffix was disabled and the config change would not have rolled.

The stale ConfigMap remains — this is the point that motivates GitOps `prune`:

```
$ kubectl -n kcna-lab21 get configmap | grep tracklane-config-dev
tracklane-config-dev-f2c68b9047   4      2m
tracklane-config-dev-m889h8f92h   4      6m
```

**Required signal:** two ConfigMaps. `kubectl apply -k` has no garbage collection.

---

## Step 8 — GitOps manifests

```
$ kubectl apply --dry-run=client -f gitops/argocd-application.yaml
error: resource mapping not found for name: "tracklane-dev" namespace: "argocd" from "gitops/argocd-application.yaml": no matches for kind "Application" in version "argoproj.io/v1alpha1"
ensure CRDs are installed first
```

**This error is the expected and desired result.** It demonstrates that a GitOps controller is an ordinary controller that installs a CRD — nothing more. It is also why these files live in `gitops/` and not in `manifests/`.

```
$ grep -E '^(kind|  name|  interval|  path|  prune|  targetNamespace):' gitops/flux-kustomization.yaml
kind: GitRepository
  name: tracklane
  interval: 1m
kind: Kustomization
  name: tracklane-dev
  interval: 5m
  path: ./courseware/labs/lab-21-helm-kustomize-gitops/kustomize/overlays/dev
  prune: true
  targetNamespace: kcna-lab21
```

---

## Graded checks

### Full environment (helm installed, cluster reachable, after Step 7)

```
$ bash verification/checks.sh
== Lab 21 verification — static render (no cluster required) ==
[PASS] chart/ contains Chart.yaml, values.yaml, _helpers.tpl and 3 templates
[PASS] Chart.yaml declares apiVersion v2, name tracklane and a semver version
[PASS] no ':latest' image tag anywhere in chart/, kustomize/ or manifests/
[PASS] kubectl kustomize renders overlays/dev
[PASS] kubectl kustomize renders overlays/prod
[PASS] both rendered overlays pass kubectl apply --dry-run=client
[PASS] overlays/dev matches data/release-inventory.csv (suffix -dev, 1 replicas, 50m/64Mi, 4 lanes, LOG_LEVEL=debug)
[PASS] overlays/prod matches data/release-inventory.csv (suffix -prod, 3 replicas, 100m/128Mi, 9 lanes, LOG_LEVEL=warn)
[PASS] the instance label was injected into selectors as well as metadata (includeSelectors: true)
[PASS] the prod images transformer rewrote the image to a fully-qualified registry path
[PASS] dev inherited the base image reference unchanged
[PASS] the prod JSON 6902 patch changed readinessProbe.periodSeconds 5 -> 10
[PASS] generated ConfigMap carries a content hash (tracklane-config-dev-m889h8f92h) and the Deployment reference was rewritten
[PASS] overlays/dev and overlays/prod render materially different output
[PASS] helm lint passes on chart/
[PASS] helm template renders the chart with data/values-dev.yaml
[PASS] helm template renders the chart with data/values-prod.yaml
[PASS] the values files drove replicaCount 1 (dev) and 3 (prod)
[PASS] the conditional PodDisruptionBudget renders in prod only
[PASS] the Deployment carries a checksum/config annotation
[PASS] --set-file carried all 9 rows of data/shipping-lanes.csv into the render
[PASS] the Argo CD Application lives in gitops/, not manifests/ (it needs a CRD)
[PASS] the Application declares repoURL, targetRevision, prune and selfHeal
[PASS] deployment/tracklane-dev is available in kcna-lab21 (applied from the dev overlay)
[PASS] no container in kcna-lab21 requests privileged: true
------------------------------------------------
25 passed, 0 failed, 0 skipped
```

### Static only — no helm, no cluster (the authoring machine; VERIFIED)

This is the run that was actually executed while authoring this lab:

```
$ bash verification/checks.sh
== Lab 21 verification — static render (no cluster required) ==
[PASS] chart/ contains Chart.yaml, values.yaml, _helpers.tpl and 3 templates
[PASS] Chart.yaml declares apiVersion v2, name tracklane and a semver version
[PASS] no ':latest' image tag anywhere in chart/, kustomize/ or manifests/
[PASS] kubectl kustomize renders overlays/dev
[PASS] kubectl kustomize renders overlays/prod
[SKIP] kubectl apply --dry-run=client needs a reachable cluster for discovery
[PASS] overlays/dev matches data/release-inventory.csv (suffix -dev, 1 replicas, 50m/64Mi, 4 lanes, LOG_LEVEL=debug)
[PASS] overlays/prod matches data/release-inventory.csv (suffix -prod, 3 replicas, 100m/128Mi, 9 lanes, LOG_LEVEL=warn)
[PASS] the instance label was injected into selectors as well as metadata (includeSelectors: true)
[PASS] the prod images transformer rewrote the image to a fully-qualified registry path
[PASS] dev inherited the base image reference unchanged
[PASS] the prod JSON 6902 patch changed readinessProbe.periodSeconds 5 -> 10
[PASS] generated ConfigMap carries a content hash (tracklane-config-dev-m889h8f92h) and the Deployment reference was rewritten
[PASS] overlays/dev and overlays/prod render materially different output
[SKIP] helm not installed — chart render checks skipped (see https://helm.sh/docs/intro/install/)
[SKIP] helm not installed — values-file diff checks skipped
[SKIP] helm not installed — conditional PodDisruptionBudget check skipped
[SKIP] helm not installed — checksum/config annotation check skipped
[SKIP] helm not installed — --set-file dataset check skipped
[PASS] the Argo CD Application lives in gitops/, not manifests/ (it needs a CRD)
[PASS] the Application declares repoURL, targetRevision, prune and selfHeal
[SKIP] namespace kcna-lab21 not present — cluster-state checks skipped (static grading still applies)
[SKIP] namespace kcna-lab21 not present — privileged-container check skipped
------------------------------------------------
15 passed, 0 failed, 8 skipped
```

Exit code `0`. **Skips are not failures.** The graded core — the Kustomize render compared against `data/release-inventory.csv` — passes in both environments.

---

## Failure injection A — a patch target that matches nothing (VERIFIED)

```
$ sed -i.tmp 's|^      name: tracklane$|      name: tracklane-web|' kustomize/overlays/prod/kustomization.yaml
$ kubectl kustomize kustomize/overlays/prod >/dev/null; echo "render exit=$?"
render exit=0
```

**Required signal: exit 0 with no output.** Kustomize does not warn about an unmatched patch target. There is no flag that makes it warn.

```
$ kubectl kustomize kustomize/overlays/prod | grep -A3 'requests:'
          requests:
            cpu: 50m
            memory: 64Mi
        securityContext:
$ kubectl kustomize kustomize/overlays/prod | grep 'periodSeconds:'
          periodSeconds: 5
```

Prod silently rendered the base's `50m` and the base's `periodSeconds: 5`. Both patches were no-ops.

The diff detector:

```
$ diff <(kubectl kustomize kustomize/base | grep -A3 'requests:') <(kubectl kustomize kustomize/overlays/prod | grep -A3 'requests:') && echo "NO DIFFERENCE — the prod overlay is not changing resources at all"
NO DIFFERENCE — the prod overlay is not changing resources at all
```

The graded checks catch it:

```
$ bash verification/checks.sh 2>&1 | grep -E '^\[FAIL\]|passed,'
[FAIL] overlays/prod: expected cpu request 100m
[FAIL] expected readinessProbe.periodSeconds 5 in dev and 10 in prod
13 passed, 2 failed, 8 skipped
```

Exit code `1`. **Required signal:** both silent no-ops surface as failures. Counts assume no helm and no cluster.

After restoring the file:

```
$ bash verification/checks.sh 2>&1 | tail -2
------------------------------------------------
15 passed, 0 failed, 8 skipped
```

---

## Failure injection B — the chart's guard rejects `latest` (requires helm)

```
$ helm template tracklane-dev ./chart -f data/values-dev.yaml --set image.tag=latest
Error: execution error at (tracklane/templates/deployment.yaml:50:20): image.tag must not be 'latest' — pin an immutable tag or a digest

Use --debug flag to render out invalid YAML
```

```
$ helm template tracklane-dev ./chart -f data/values-dev.yaml --set image.tag=null
Error: execution error at (tracklane/templates/deployment.yaml:50:20): image.tag is required and must be pinned
```

**Required signal:** both fail at **render time**, naming the file, line and reason. Contrast with Failure A, where Kustomize rendered successfully and did the wrong thing. Line/column `50:20` matches `chart/templates/deployment.yaml` as shipped and shifts if you edit it.

---

## Cleanup

```
$ kubectl delete namespace kcna-lab21 --wait=true
namespace "kcna-lab21" deleted

$ helm list --all-namespaces | grep tracklane || echo "no tracklane helm release exists"
no tracklane helm release exists

$ kubectl kustomize kustomize/overlays/dev >/dev/null && kubectl kustomize kustomize/overlays/prod >/dev/null && echo "both overlays still render"
both overlays still render

$ kubectl get namespace kcna-lab21
Error from server (NotFound): namespaces "kcna-lab21" not found
```

**Required end state:** no `kcna-lab21` namespace, **no Helm release** (`helm template` renders to stdout and never contacts a cluster), no CRDs, no controllers and no cluster-scoped objects. Both overlays still render, proving the failure-injection edits were reverted.
