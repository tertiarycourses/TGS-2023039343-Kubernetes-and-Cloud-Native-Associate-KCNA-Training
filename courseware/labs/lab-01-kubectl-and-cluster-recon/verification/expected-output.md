# Lab 01 — Expected evidence

Everything below is what a learner should be able to show at the end of the lab.
Node names, ages, UIDs, IP addresses and image digests will differ on your
cluster; **shape and key strings** are what matters.

---

## 1. Cluster identity

```console
$ kubectl version
Client Version: v1.37.0
Kustomize Version: v5.8.1
Server Version: v1.37.0
```

```console
$ kubectl get nodes -o wide
NAME                             STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                         KERNEL-VERSION    CONTAINER-RUNTIME
kcna-qa-20260905-control-plane   Ready    control-plane   47m   v1.37.0   172.18.0.2    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit  containerd://2.1.4
```

A single-node kind cluster shows exactly one node and it carries the
`control-plane` role. On a managed cloud cluster you would see several nodes and
the control plane would not be listed at all.

## 2. Namespace and guardrails

```console
$ kubectl apply -f manifests/00-namespace.yaml
namespace/kcna-lab01 created

$ kubectl apply -f manifests/10-namespace-guardrails.yaml
resourcequota/depot-recon-quota created
limitrange/depot-recon-defaults created

$ kubectl -n kcna-lab01 get resourcequota depot-recon-quota
NAME                AGE   REQUEST                                                  LIMIT
depot-recon-quota   9s    count/configmaps: 0/10, pods: 0/10, requests.cpu: 0/1,   limits.cpu: 0/2, limits.memory: 0/2Gi
                          requests.memory: 0/1Gi
```

## 3. API discovery

```console
$ kubectl api-versions | head -n 8
admissionregistration.k8s.io/v1
apiextensions.k8s.io/v1
apiregistration.k8s.io/v1
apps/v1
authentication.k8s.io/v1
authorization.k8s.io/v1
autoscaling/v1
autoscaling/v2
```

```console
$ kubectl api-resources --api-group='' --no-headers | head -n 6
bindings                      true    Binding
configmaps         cm         true    ConfigMap
endpoints          ep         true    Endpoints
events             ev         true    Event
limitranges        limits     true    LimitRange
namespaces         ns         false   Namespace
```

Column 3 is `NAMESPACED`. `namespaces` itself is `false` — namespaces are
cluster-scoped, which is why `kubectl get ns -n something` is meaningless.

## 4. Baseline diff

```console
$ kubectl api-resources --api-group='' --no-headers | awk '{print $1}' | sort > /tmp/live-core.txt
$ grep -v '^#' data/core-api-inventory.tsv | cut -f1 | sort > /tmp/baseline-core.txt
$ comm -23 /tmp/baseline-core.txt /tmp/live-core.txt
```

Empty output = every baseline resource is served by this cluster. That is the
pass condition. The reverse direction shows what this cluster serves *beyond*
the baseline:

```console
$ comm -13 /tmp/baseline-core.txt /tmp/live-core.txt
bindings
endpoints
```

`endpoints` appears because v1 Endpoints is deprecated (v1.33) but still served.

## 5. Schema exploration

```console
$ kubectl explain pod.spec.containers.resources
GROUP:      
KIND:       Pod
VERSION:    v1

FIELD: resources <ResourceRequirements>

DESCRIPTION:
    Compute Resources required by this container. Cannot be updated.

FIELDS:
  claims        <[]ResourceClaim>
  limits        <map[string]Quantity>
  requests      <map[string]Quantity>
```

## 6. The Pod and the mounted dataset

```console
$ kubectl -n kcna-lab01 get pod recon-shell
NAME          READY   STATUS    RESTARTS   AGE
recon-shell   1/1     Running   0          21s

$ kubectl -n kcna-lab01 logs recon-shell | tail -n 4
RC-011,state,What does the API server store for one object?,kubectl get pod recon-shell -n kcna-lab01 -o yaml,metadata.uid resourceVersion and status blocks
RC-012,events,What has the control plane recently done here?,kubectl get events -n kcna-lab01 --sort-by=.lastTimestamp,Scheduled Pulled Created Started
[recon-shell] checklist rows: 13
[recon-shell] holding open for kubectl exec
```

## 7. kubectl is an HTTP client

```console
$ kubectl -n kcna-lab01 get pods --v=6
I0905 15:44:02.118374   62311 loader.go:395] Config loaded from file:  /tmp/kcna-kind-20260905/kubeconfig
I0905 15:44:02.146902   62311 round_trippers.go:553] GET https://127.0.0.1:52913/api/v1/namespaces/kcna-lab01/pods?limit=500 200 OK in 21 milliseconds
NAME          READY   STATUS    RESTARTS   AGE
recon-shell   1/1     Running   0          64s
```

## 8. Verification script

```console
$ bash verification/checks.sh

== 0. kubectl and cluster reachability
  [PASS] kubectl can reach the API server

== 1. Namespace and namespaced policy objects
  [PASS] namespace kcna-lab01 exists
  [PASS] ResourceQuota depot-recon-quota exists
  [PASS] LimitRange depot-recon-defaults exists

== 2. ConfigMap built from data/recon-checklist.csv
  [PASS] ConfigMap recon-checklist exists
  [PASS] ConfigMap carries key recon-checklist.csv
  [PASS] ConfigMap content includes checklist row RC-010

== 3. recon-shell Pod
  [PASS] Pod recon-shell phase is Running
  [PASS] container 'shell' reports ready=true
  [PASS] recon-shell logs report 13 lines (CSV header plus 12 checklist records) read from the mounted CSV

== 4. Core API inventory matches data/core-api-inventory.tsv
  [PASS] all 14 baseline core resources are served by this cluster

== 5. kubectl explain reaches the live OpenAPI schema
  [PASS] kubectl explain pod.spec.containers.resources returns the 'requests' field

== 6. Verbose mode exposes the REST call
  [PASS] --v=6 shows GET .../api/v1/namespaces/kcna-lab01/pods

Result: 14 passed, 0 failed
```
