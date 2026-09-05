# Lab 18 — expected output

Reference transcript for **Lab 18 · PersistentVolumes, Claims and StorageClasses**, namespace `kcna-lab18`.

> **How to read this file.** UUIDs, timestamps, ages, Pod names, Pod IPs and node names are environment-specific and **will differ**. Object names, phases, capacities, access modes, reclaim policies, row counts and error strings must match exactly.
>
> The `VOLUMEATTRIBUTESCLASS` column appears on Kubernetes v1.29+ clients and shows `<unset>`; on older clients it is absent. Either is fine.

---

## Prerequisite survey — what kind gives you

```
$ kubectl get storageclass
NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
standard (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  41m

$ kubectl -n local-path-storage get pods
NAME                                      READY   STATUS    RESTARTS   AGE
local-path-provisioner-7dc846544d-mrxsq   1/1     Running   0          41m
```

**Required signal:** exactly one class, named `standard`, marked `(default)`, provisioner `rancher.io/local-path`, `Delete`, `WaitForFirstConsumer`. If your cluster shows a different default class the rest of the lab still works, but Step 9's `Pending` behaviour depends on `WaitForFirstConsumer` — check your class's binding mode before assuming a fault.

```
$ kubectl get csidrivers
No resources found
```

Empty is expected on stock kind: local-path-provisioner predates CSI and is not a CSI driver.

---

## Step 1 — datasets

```
$ echo "rows: $(( $(wc -l < data/manifest-archive.csv) - 1 ))"
rows: 30

$ kubectl -n kcna-lab18 create configmap tracklane-archive-seed --from-file=manifest-archive.csv=data/manifest-archive.csv
configmap/tracklane-archive-seed created
$ kubectl -n kcna-lab18 create configmap tracklane-retention-policy --from-file=retention-policy.csv=data/retention-policy.csv
configmap/tracklane-retention-policy created
```

---

## Step 3 — static PV

```
$ kubectl get pv tracklane-archive-pv
NAME                   CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM                      STORAGECLASS       VOLUMEATTRIBUTESCLASS   REASON   AGE
tracklane-archive-pv   1Gi        RWO            Retain           Available   kcna-lab18/archive-claim   tracklane-manual   <unset>                          6s
```

**Required signal:** `STATUS=Available` **and** `CLAIM` already populated from `claimRef` before any PVC exists.

```
$ kubectl get pv tracklane-archive-pv -o jsonpath='{.metadata.namespace}{"[end]"}{"\n"}'
[end]
```

Empty before `[end]` proves the object is cluster-scoped.

---

## Step 4 — immediate static binding

```
$ kubectl -n kcna-lab18 get pvc archive-claim
NAME            STATUS   VOLUME                 CAPACITY   ACCESS MODES   STORAGECLASS       VOLUMEATTRIBUTESCLASS   AGE
archive-claim   Bound    tracklane-archive-pv   1Gi        RWO            tracklane-manual   <unset>                 4s
```

**Required signal:** `Bound` within a few seconds (no `WaitForFirstConsumer` here — `tracklane-manual` names no StorageClass, so there is no binding mode to honour), and `CAPACITY=1Gi` despite a 512Mi request.

```
$ kubectl get pv tracklane-archive-pv -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,CLAIM:.spec.claimRef.name,UID:.spec.claimRef.uid'
NAME                   STATUS   CLAIM           UID
tracklane-archive-pv   Bound    archive-claim   1c9f4a02-6e5b-4d81-93a7-0b2e5f7c4d16
```

The UID is populated by the controller and will differ on your cluster.

---

## Step 5 — seeding the volume

```
$ kubectl -n kcna-lab18 logs archive-seeder
wrote 30 archive rows to the PersistentVolume
sealed_by=archive-seeder
sealed_utc=2026-09-05T05:02:41Z
archive_rows=30
retention_class=gold
```

`30` must match `wc -l data/manifest-archive.csv` minus one. `sealed_utc` varies.

```
$ kubectl -n kcna-lab18 delete pod archive-seeder --wait=true
pod "archive-seeder" deleted
$ kubectl -n kcna-lab18 get pods
No resources found in kcna-lab18 namespace.
```

---

## Step 6 — persistence proof

```
$ kubectl -n kcna-lab18 logs archive-auditor
--- provenance written by the (now deleted) seeder Pod ---
sealed_by=archive-seeder
sealed_utc=2026-09-05T05:02:41Z
archive_rows=30
retention_class=gold
--- archive row count as read back ---
rows_read=30
--- can this auditor modify the archive? ---
read-only mount refused the write (expected)
```

**This is the core result of the lab.** `sealed_by=archive-seeder` and `sealed_utc` are byte-identical to Step 5, read by a Pod that did not write them. `rows_read=30`.

---

## Step 8 — second StorageClass

```
$ kubectl get storageclass
NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
standard (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  52m
tracklane-retain     rancher.io/local-path   Retain          WaitForFirstConsumer   false                  5s
```

Same provisioner, different `RECLAIMPOLICY`. That contrast is the point.

---

## Step 9 — the expected `Pending`

```
$ kubectl -n kcna-lab18 get pvc render-cache
NAME           STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
render-cache   Pending                                      standard       <unset>                 8s

$ kubectl -n kcna-lab18 describe pvc render-cache | tail -8
Used By:       <none>
Events:
  Type    Reason                Age               From                         Message
  ----    ------                ----              ----                         -------
  Normal  WaitForFirstConsumer  3s (x2 over 10s)  persistentvolume-controller  waiting for first consumer to be created before binding
```

**Required signal:** `Type: Normal`, `Reason: WaitForFirstConsumer`. This is **not** a defect. Repeat counts grow while you wait.

---

## Step 10 — binding on first consumer

```
$ kubectl -n kcna-lab18 rollout status deployment/render-cache --timeout=180s
deployment "render-cache" successfully rolled out

$ kubectl -n kcna-lab18 get pvc render-cache
NAME           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
render-cache   Bound    pvc-8b2e17d4-05c9-4f36-a1b7-e39d602c8a54   256Mi      RWO            standard       <unset>                 2m41s
```

**Required signal:** `Bound`, and the volume name begins `pvc-` followed by a UUID (yours will differ).

```
$ kubectl -n kcna-lab18 logs deployment/render-cache
--- /cache/starts.log ---
start render-cache-6c9f84b57d-x2klp 2026-09-05T05:14:08Z
--- bronze-tier datasets from the retention policy ---
tracking-render-cache
lane-etl-scratch
```

The two bronze-tier dataset names come from `data/retention-policy.csv` and must appear exactly.

After `rollout restart`:

```
$ kubectl -n kcna-lab18 logs deployment/render-cache | head -4
--- /cache/starts.log ---
start render-cache-6c9f84b57d-x2klp 2026-09-05T05:14:08Z
start render-cache-7fb5d9c684-qn8vt 2026-09-05T05:15:52Z
```

**Required signal:** two `start` lines with different Pod names. One line means the volume was re-provisioned rather than reused — check the PVC did not get recreated.

---

## Step 12 — Retain, Released and manual re-admission

```
$ kubectl get pv tracklane-archive-pv
NAME                   CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS     CLAIM                      STORAGECLASS       VOLUMEATTRIBUTESCLASS   REASON   AGE
tracklane-archive-pv   1Gi        RWO            Retain           Released   kcna-lab18/archive-claim   tracklane-manual   <unset>                          17m
```

**Required signal:** `Released`, not `Available` and not gone.

Recreated claim will not bind:

```
$ kubectl -n kcna-lab18 get pvc archive-claim
NAME            STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS       VOLUMEATTRIBUTESCLASS   AGE
archive-claim   Pending                                      tracklane-manual   <unset>                 10s
```

After clearing the stale `claimRef.uid`:

```
$ kubectl patch pv tracklane-archive-pv --type=json -p='[{"op":"remove","path":"/spec/claimRef/uid"},{"op":"remove","path":"/spec/claimRef/resourceVersion"}]'
persistentvolume/tracklane-archive-pv patched

$ kubectl -n kcna-lab18 get pvc archive-claim
NAME            STATUS   VOLUME                 CAPACITY   ACCESS MODES   STORAGECLASS       VOLUMEATTRIBUTESCLASS   AGE
archive-claim   Bound    tracklane-archive-pv   1Gi        RWO            tracklane-manual   <unset>                 33s
```

And the data is untouched:

```
$ kubectl -n kcna-lab18 logs archive-auditor
--- provenance written by the (now deleted) seeder Pod ---
sealed_by=archive-seeder
sealed_utc=2026-09-05T05:02:41Z
...
rows_read=30
```

`sealed_utc` must equal the value from Step 5 — that is the proof the release/re-admit cycle preserved the bytes.

---

## Graded checks

```
$ bash verification/checks.sh
== Lab 18 verification — namespace kcna-lab18 ==
[PASS] namespace kcna-lab18 exists
[PASS] PersistentVolume tracklane-archive-pv exists and is cluster-scoped
[PASS] tracklane-archive-pv capacity=1Gi accessMode=ReadWriteOnce reclaim=Retain
[PASS] tracklane-archive-pv is pre-bound via claimRef to kcna-lab18/archive-claim
[PASS] pvc/archive-claim is Bound to tracklane-archive-pv
[PASS] archive-claim requested 512Mi but was granted the PV's full 1Gi
[PASS] the archive on the PV holds 30 rows (matches data/manifest-archive.csv)
[PASS] PROVENANCE on the PV was written by a Pod that no longer exists
[PASS] storageclass tracklane-retain exists with reclaimPolicy=Retain
[PASS] tracklane-retain uses volumeBindingMode=WaitForFirstConsumer
[PASS] pvc/render-cache is Bound to a dynamically provisioned pvc-* volume
[PASS] the dynamic PV inherited reclaimPolicy=Delete from storageclass standard
[PASS] deployment/render-cache is available and mounts pvc/render-cache
[PASS] /cache/starts.log survived a rollout restart (2 start records)
------------------------------------------------
14 passed, 0 failed
```

Exit code `0`.

---

## Failure injection — StorageClass name typo

```
$ kubectl -n kcna-lab18 describe pvc archive-claim-typo
Name:          archive-claim-typo
Namespace:     kcna-lab18
StorageClass:  tracklane-manul
Status:        Pending
Volume:
Finalizers:    [kubernetes.io/pvc-protection]
Used By:       <none>
Events:
  Type     Reason              Age               From                         Message
  ----     ------              ----              ----                         -------
  Warning  ProvisioningFailed  4s (x3 over 18s)  persistentvolume-controller  storageclass.storage.k8s.io "tracklane-manul" not found
```

**Required signal:** `Type: Warning`, `Reason: ProvisioningFailed`, and the literal string `storageclass.storage.k8s.io "tracklane-manul" not found`. Contrast with the `Normal / WaitForFirstConsumer` in Step 9 — that distinction is the graded diagnostic skill.

Immutability proof:

```
$ kubectl -n kcna-lab18 patch pvc archive-claim -p '{"spec":{"storageClassName":"standard"}}'
The PersistentVolumeClaim "archive-claim" is invalid: spec: Forbidden: spec is immutable after creation except resources.requests and volumeAttributesClassName for bound claims
```

The exact wording of the "except ..." clause varies slightly by minor version; the `Forbidden: spec is immutable` prefix is stable.

---

## Cleanup

```
$ kubectl delete namespace kcna-lab18 --wait=true
namespace "kcna-lab18" deleted

$ kubectl get pv | grep kcna-lab18
tracklane-archive-pv   1Gi   RWO   Retain   Released   kcna-lab18/archive-claim   tracklane-manual   <unset>   38m

$ kubectl delete persistentvolume tracklane-archive-pv
persistentvolume "tracklane-archive-pv" deleted

$ kubectl delete storageclass tracklane-retain
storageclass.storage.k8s.io "tracklane-retain" deleted

$ kubectl get storageclass
NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
standard (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  81m

$ kubectl get pv
No resources found
```

**Required end state:** only the original `standard` StorageClass remains, no PersistentVolumes remain, and `kcna-lab18` is gone. The dynamic PV for `render-cache` disappeared on its own because its class reclaim policy is `Delete`; `tracklane-archive-pv` survived because its policy is `Retain` and had to be removed by explicit name.
