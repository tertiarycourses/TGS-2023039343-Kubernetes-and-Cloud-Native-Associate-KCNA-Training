# Lab 05 — Expected evidence

Digests, runtime versions and sizes are cluster-specific. **Structure and marker
strings** are what you compare against.

---

## 1. The runtime behind the CRI socket

```console
$ kubectl get nodes -o wide
NAME                             STATUS   ROLES           AGE    VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                         KERNEL-VERSION     CONTAINER-RUNTIME
kcna-qa-20260905-control-plane   Ready    control-plane   102m   v1.37.0   172.18.0.2    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://2.1.4
```

```console
$ kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.containerRuntimeVersion}{"\n"}'
containerd://2.1.4
```

## 2. The node's image store, straight from the Node object

```console
$ kubectl get nodes -o jsonpath='{range .items[0].status.images[*]}{.sizeBytes}{"\t"}{.names[0]}{"\n"}{end}' | sort -rn | head -n 6
147718971	registry.k8s.io/etcd@sha256:e78e30bb5c2ea9d2b0f8b1a2f9e1bd5e9e9b3f18ea9d1c0b2b74f6c3e2e9b40d2
92632544	registry.k8s.io/kube-apiserver@sha256:1a1f05a2cd7c2b2e3e0f1a45c7c7f74a4e3fdc7fbc25da8b0e0d84a8b7f6cf12
21674089	docker.io/library/nginx@sha256:3d696e8357051647b844d8c7cf4a0aa71e84379999a4f6af9b8ca1f7919ade42
4264178	docker.io/library/alpine@sha256:beefdbd8a1da6d2915566fde36db9db0b524eb737fc57cd1367effd16dc0d06d
4042190	docker.io/library/busybox@sha256:2376a0c12759aa1214ba83e771ff252c7b1663216b192fbe5e0fb364e952f85c
744000	registry.k8s.io/pause@sha256:7031c1b283388d2c2e09b57badb803c05ebed362dc88d84b480cc47f72a21097
```

Every entry is `repository@sha256:...`. The node's store is **content
addressed**; tags are just labels that point into it.

## 3. Tag-pinned Pod: asked-for vs resolved

```console
$ kubectl -n kcna-lab05 get pod image-catalog
NAME            READY   STATUS    RESTARTS   AGE
image-catalog   1/1     Running   0          24s

$ kubectl -n kcna-lab05 get pod image-catalog -o jsonpath='{.spec.containers[0].image}{"\n"}'
nginx:1.27-alpine

$ kubectl -n kcna-lab05 get pod image-catalog -o jsonpath='{.status.containerStatuses[0].image}{"\n"}'
docker.io/library/nginx:1.27-alpine

$ kubectl -n kcna-lab05 get pod image-catalog -o jsonpath='{.status.containerStatuses[0].imageID}{"\n"}'
docker.io/library/nginx@sha256:3d696e8357051647b844d8c7cf4a0aa71e84379999a4f6af9b8ca1f7919ade42
```

Three different strings for one image:

| Field | Value | Meaning |
|---|---|---|
| `spec.…image` | `nginx:1.27-alpine` | what **you** wrote |
| `status.…image` | `docker.io/library/nginx:1.27-alpine` | what the reference **normalises** to |
| `status.…imageID` | `docker.io/library/nginx@sha256:3d69…` | what the runtime actually **resolved and ran** |

## 4. Datasets served

```console
$ kubectl -n kcna-lab05 exec image-catalog -c web -- wget -qO- http://127.0.0.1/image-inventory.csv | grep -v '^#'
component,image_ref,registry,repository,tag,pin_style,approx_size_mb,base,notes
depot-web,nginx:1.27-alpine,docker.io,library/nginx,1.27-alpine,tag,22,alpine,static content only
depot-api,busybox:1.36,docker.io,library/busybox,1.36,tag,2,scratch+busybox,PoC stand-in for the Go API
depot-jobs,alpine:3.20,docker.io,library/alpine,3.20,tag,4,alpine,batch and cron workloads
depot-sandbox,registry.k8s.io/pause:3.9,registry.k8s.io,pause,3.9,tag,1,scratch,pod sandbox infra container
depot-web-locked,nginx@sha256:<digest>,docker.io,library/nginx,none,digest,22,alpine,production pin - digest resolved at release time
```

```console
$ kubectl -n kcna-lab05 exec image-catalog -c web -- wget -qO- http://127.0.0.1/reference-forms.tsv | grep -v '^#' | head -n 3
nginx	docker.io/library/nginx:latest	none - tag is mutable AND implicit
nginx:1.27-alpine	docker.io/library/nginx:1.27-alpine	weak - tag can be re-pointed
library/nginx:1.27-alpine	docker.io/library/nginx:1.27-alpine	weak - same as above
```

## 5. imagePullPolicy matrix

```console
$ kubectl -n kcna-lab05 get pods -o custom-columns='NAME:.metadata.name,IMAGE:.spec.containers[0].image,POLICY:.spec.containers[0].imagePullPolicy,STATUS:.status.containerStatuses[0].state'
NAME              IMAGE                                                          POLICY         STATUS
image-catalog     nginx:1.27-alpine                                              IfNotPresent   map[running:...]
pp-always         busybox:1.36                                                   Always         map[running:...]
pp-ifnotpresent   busybox:1.36                                                   IfNotPresent   map[running:...]
pp-never          meridianfreight.example.com/depot-portal/depot-api:0.1.0-poc   Never          map[waiting:map[message:Container image "..." is not present with pull policy of Never reason:ErrImageNeverPull]]
```

```console
$ kubectl -n kcna-lab05 get pod pp-never
NAME       READY   STATUS              RESTARTS   AGE
pp-never   0/1     ErrImageNeverPull   0          19s

$ kubectl -n kcna-lab05 describe pod pp-never | tail -n 5
Events:
  Type     Reason             Age               From               Message
  ----     ------             ----              ----               -------
  Normal   Scheduled          21s               default-scheduler  Successfully assigned kcna-lab05/pp-never to kcna-qa-20260905-control-plane
  Warning  ErrImageNeverPull  6s (x3 over 21s)  kubelet            Container image "meridianfreight.example.com/depot-portal/depot-api:0.1.0-poc" is not present with pull policy of Never
```

There is **no `Pulling` event** — with `Never` the kubelet does not contact a
registry at all.

Events for the two working policies:

```console
$ kubectl -n kcna-lab05 describe pod pp-always | grep -E 'Pulling|Pulled'
  Normal  Pulling  30s   kubelet  Pulling image "busybox:1.36"
  Normal  Pulled   28s   kubelet  Successfully pulled image "busybox:1.36" in 1.842s (1.842s including waiting). Image size: 4042190 bytes.

$ kubectl -n kcna-lab05 describe pod pp-ifnotpresent | grep -E 'Pulling|Pulled'
  Normal  Pulled  30s   kubelet  Container image "busybox:1.36" already present on machine
```

`already present on machine` with no preceding `Pulling` is the whole difference.

## 6. Failure injection — stale digest

```console
$ kubectl apply -f manifests/20-digest-pinned.yaml
pod/depot-web-locked created

$ kubectl -n kcna-lab05 get pod depot-web-locked
NAME               READY   STATUS         RESTARTS   AGE
depot-web-locked   0/1     ErrImagePull   0          7s
```

```console
$ kubectl -n kcna-lab05 describe pod depot-web-locked | tail -n 8
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  48s                default-scheduler  Successfully assigned kcna-lab05/depot-web-locked to kcna-qa-20260905-control-plane
  Normal   Pulling    18s (x3 over 48s)  kubelet            Pulling image "nginx@sha256:9c1b5b6f0f6cc1e7d0d2a3c4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718"
  Warning  Failed     17s (x3 over 47s)  kubelet            Failed to pull image "nginx@sha256:9c1b5b6f...": failed to pull and unpack image "docker.io/library/nginx@sha256:9c1b5b6f...": failed to resolve reference "docker.io/library/nginx@sha256:9c1b5b6f...": docker.io/library/nginx@sha256:9c1b5b6f...: not found
  Warning  Failed     17s (x3 over 47s)  kubelet            Error: ErrImagePull
  Normal   BackOff    3s (x4 over 46s)   kubelet            Back-off pulling image "nginx@sha256:9c1b5b6f..."
  Warning  Failed     3s (x4 over 46s)   kubelet            Error: ImagePullBackOff
```

Repair using the digest this cluster resolved:

```console
$ DIGEST=$(kubectl -n kcna-lab05 get pod image-catalog -o jsonpath='{.status.containerStatuses[0].imageID}')
$ echo "$DIGEST"
docker.io/library/nginx@sha256:3d696e8357051647b844d8c7cf4a0aa71e84379999a4f6af9b8ca1f7919ade42

$ kubectl -n kcna-lab05 set image pod/depot-web-locked "web=nginx@${DIGEST##*@}"
pod/depot-web-locked image updated

$ kubectl -n kcna-lab05 get pod depot-web-locked
NAME               READY   STATUS    RESTARTS   AGE
depot-web-locked   1/1     Running   0          2m11s

$ kubectl -n kcna-lab05 get pod depot-web-locked -o jsonpath='{.spec.containers[0].image}{"\n"}{.status.containerStatuses[0].imageID}{"\n"}'
nginx@sha256:3d696e8357051647b844d8c7cf4a0aa71e84379999a4f6af9b8ca1f7919ade42
docker.io/library/nginx@sha256:3d696e8357051647b844d8c7cf4a0aa71e84379999a4f6af9b8ca1f7919ade42
```

With a digest pin, `spec.image` and `status.imageID` name the **same content**.
That is the definition of a reproducible deployment.

## 7. Verification script

```console
$ bash verification/checks.sh

== 0. Cluster reachability
  [PASS] kubectl can reach the API server

== 1. Namespace and catalog ConfigMap built from data/
  [PASS] namespace kcna-lab05 exists
  [PASS] ConfigMap image-catalog carries image-inventory.csv
  [PASS] ConfigMap image-catalog carries reference-forms.tsv

== 2. The runtime this node actually uses (CRI)
  [PASS] node reports a CRI runtime: containerd://2.1.4

== 3. Tag-pinned catalog Pod
  [PASS] Pod image-catalog is Ready
  [PASS] spec.containers[0].image is the TAG you asked for (nginx:1.27-alpine)
  [PASS] status.imageID resolved to a content-addressed digest
  [PASS] digest is a well-formed sha256:<64 hex> string

== 4. The dataset is really being served
  [PASS] GET /image-inventory.csv returns the Meridian inventory
  [PASS] GET /reference-forms.tsv returns the reference normalisation card

== 5. Governance: running images vs the approved inventory
  [PASS] image-catalog runs an image listed in data/image-inventory.csv
  [PASS] pp-never runs an unapproved image (meridianfreight.example.com/depot-portal/depot-api:0.1.0-poc) — drift is detectable from data/

== 6. imagePullPolicy matrix
  [PASS] pp-always declares imagePullPolicy: Always
  [PASS] pp-ifnotpresent declares imagePullPolicy: IfNotPresent
  [PASS] pp-never declares imagePullPolicy: Never
  [PASS] pp-never is ErrImageNeverPull — the kubelet never contacted a registry

== 7. Digest-pinned Pod
  [PASS] depot-web-locked is pinned by digest, not by tag
  [PASS] depot-web-locked is Ready — you substituted a digest this cluster can resolve
  [PASS] the repaired digest matches image-catalog's resolved digest exactly

Result: 19 passed, 0 failed
```

If you run the script before repairing `depot-web-locked`, section 7 prints
`[SKIP] depot-web-locked is still ImagePullBackOff — you are mid-way through
section 6` and the total is `17 passed, 0 failed`.
