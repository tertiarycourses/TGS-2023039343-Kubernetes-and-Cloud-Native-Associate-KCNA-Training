# Lab 02 — Expected evidence

UIDs, ages, IPs and node names will differ. The **strings and structure** below
are what a correct run looks like.

---

## 1. Authoring aids

```console
$ kubectl run depot-web --image=nginx:1.27-alpine --port=80 --dry-run=client -o yaml
apiVersion: v1
kind: Pod
metadata:
  creationTimestamp: null
  labels:
    run: depot-web
  name: depot-web
spec:
  containers:
  - image: nginx:1.27-alpine
    name: depot-web
    ports:
    - containerPort: 80
    resources: {}
  dnsPolicy: ClusterFirst
  restartPolicy: Always
status: {}
```

Note `resources: {}` — the generator never writes requests or limits. That is
why you finish the manifest by hand.

## 2. ConfigMap built from `data/`

```console
$ kubectl -n kcna-lab02 create configmap depot-content \
    --from-file=index.html=data/depot-status.html \
    --from-file=depots.csv=data/depots.csv
configmap/depot-content created

$ kubectl -n kcna-lab02 get configmap depot-content -o jsonpath='{range $.data}{"\n"}{end}' >/dev/null
$ kubectl -n kcna-lab02 describe configmap depot-content | head -n 8
Name:         depot-content
Namespace:    kcna-lab02
Labels:       <none>
Annotations:  <none>

Data
====
depots.csv:
```

## 3. The Pod

```console
$ kubectl apply -f manifests/20-depot-web-pod.yaml
pod/depot-web created

$ kubectl -n kcna-lab02 get pod depot-web -o wide
NAME        READY   STATUS    RESTARTS   AGE   IP           NODE                             NOMINATED NODE   READINESS GATES
depot-web   1/1     Running   0          18s   10.244.0.11  kcna-qa-20260905-control-plane   <none>           <none>
```

`READY 1/1` means the readinessProbe against `/index.html` succeeded.

## 4. Server-side defaulting

```console
$ kubectl -n kcna-lab02 get pod depot-web -o jsonpath='{.spec.dnsPolicy}{"\t"}{.spec.serviceAccountName}{"\t"}{.spec.schedulerName}{"\n"}'
ClusterFirst	default	default-scheduler
```

None of those three fields were in your manifest.

## 5. Content actually served

```console
$ kubectl -n kcna-lab02 exec depot-web -c web -- wget -qO- http://127.0.0.1/index.html | head -n 3
<!DOCTYPE html>
<html lang="en">
<head>

$ kubectl -n kcna-lab02 exec depot-web -c web -- wget -qO- http://127.0.0.1/depots.csv | head -n 3
depot_code,depot_name,region,bays,cold_chain,shift_pattern,last_audit
MF-SIN-01,Jurong Port Depot,Singapore West,24,yes,3x8,2026-07-14
MF-SIN-02,Tuas Megahub,Singapore West,48,yes,3x8,2026-08-02
```

Via port-forward from your workstation:

```console
$ kubectl -n kcna-lab02 port-forward pod/depot-web 8080:80
Forwarding from 127.0.0.1:8080 -> 80
Forwarding from [::1]:8080 -> 80
Handling connection for 8080
```

```console
$ curl -s http://127.0.0.1:8080/ | grep STATUS
  <p class="ok">STATUS: OK — served from a Pod in namespace kcna-lab02</p>
```

## 6. Failure injection — ImagePullBackOff

```console
$ kubectl apply -f manifests/90-depot-web-badtag.yaml
pod/depot-web-badtag created

$ kubectl -n kcna-lab02 get pod depot-web-badtag
NAME               READY   STATUS         RESTARTS   AGE
depot-web-badtag   0/1     ErrImagePull   0          8s

$ kubectl -n kcna-lab02 get pod depot-web-badtag
NAME               READY   STATUS             RESTARTS   AGE
depot-web-badtag   0/1     ImagePullBackOff   0          45s
```

```console
$ kubectl -n kcna-lab02 describe pod depot-web-badtag | tail -n 9
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  62s                default-scheduler  Successfully assigned kcna-lab02/depot-web-badtag to kcna-qa-20260905-control-plane
  Normal   Pulling    22s (x3 over 62s)  kubelet            Pulling image "nginx:1.27-alpin"
  Warning  Failed     21s (x3 over 61s)  kubelet            Failed to pull image "nginx:1.27-alpin": failed to pull and unpack image "docker.io/library/nginx:1.27-alpin": failed to resolve reference "docker.io/library/nginx:1.27-alpin": docker.io/library/nginx:1.27-alpin: not found
  Warning  Failed     21s (x3 over 61s)  kubelet            Error: ErrImagePull
  Normal   BackOff    8s (x4 over 60s)   kubelet            Back-off pulling image "nginx:1.27-alpin"
  Warning  Failed     8s (x4 over 60s)   kubelet            Error: ImagePullBackOff
```

```console
$ kubectl -n kcna-lab02 get pod depot-web-badtag \
    -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}{"\n"}'
ImagePullBackOff
```

## 7. Verification script

```console
$ bash verification/checks.sh

== 0. Cluster reachability
  [PASS] kubectl can reach the API server

== 1. Namespace
  [PASS] namespace kcna-lab02 exists

== 2. ConfigMap depot-content is built from data/
  [PASS] ConfigMap depot-content exists (keys: depots.csv index.html )
  [PASS] key index.html present
  [PASS] key depots.csv present
  [PASS] ConfigMap depots.csv row count matches data/depots.csv (10 depots)

== 3. Pod depot-web
  [PASS] Pod depot-web phase is Running
  [PASS] container 'web' passed its readinessProbe (ready=true)
  [PASS] image is pinned to nginx:1.27-alpine (no :latest)
  [PASS] containerPort 80 declared and named 'http'
  [PASS] explicit resources set (requests.cpu=50m, limits.memory=128Mi)

== 4. Content is served from the mounted ConfigMap
  [PASS] GET /index.html returns the Meridian Freight page
  [PASS] GET /depots.csv returns the synthetic depot dataset

== 5. Server-side defaulting is observable
  [PASS] API server defaulted dnsPolicy=ClusterFirst and serviceAccountName=default

== 6. Failure-injection Pod (only if you left it in place)
  [PASS] depot-web-badtag is in ImagePullBackOff as designed

Result: 14 passed, 0 failed
```

If you already deleted `depot-web-badtag`, section 6 prints
`[SKIP] depot-web-badtag not present` and the total is `13 passed, 0 failed`.
