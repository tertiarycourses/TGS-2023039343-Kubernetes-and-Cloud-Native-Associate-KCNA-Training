# Lab 06 — Expected verification evidence

Run from the lab directory:

```bash
bash verification/checks.sh
```

## Expected transcript

```
Lab 06 verification - namespace kcna-lab06

== Namespace
  [PASS] namespace kcna-lab06 is Active (= Active)

== ConfigMap built from data/service-inventory.csv
  [PASS] configmap service-inventory carries the CSV header (= service_name)
  [PASS] data file present, 3 edge-tier services declared in the inventory

== ReplicaSet tracking-api (matchLabels)
  [PASS] tracking-api desired replicas (= 3)
  [PASS] tracking-api ready replicas (= 3)
  [PASS] tracking-api selector matchLabels.app (= tracking-api)

== Adoption: the hand-created Pod is owned by the ReplicaSet
  [PASS] tracking-api-legacy adopted by ReplicaSet/tracking-api

== Selector arithmetic
  [PASS] at least 3 Pods match -l app=tracking-api,tier=edge (found 3)
  [PASS] set-based selector returns >=5 Pods (found 5)

== ReplicaSet berth-status (matchExpressions)
  [PASS] berth-status ready replicas (= 2)
  [PASS] berth-status selector uses NotIn, Exists and In (NotIn Exists In)

== Data-driven audit Pod
  [PASS] label-audit Pod phase (= Succeeded)
  [PASS] label-audit printed AUDIT-COMPLETE
  [PASS] audit Pod listed the edge services from the CSV (= 3)

----------------------------------------
Lab 06: 14 passed, 0 failed
ALL CHECKS PASSED
```

Exit status:

```bash
echo $?
```

```
0
```

## Supporting evidence the learner should be able to produce

**1. Adoption changed ownership of a Pod nobody else created**

```bash
kubectl -n kcna-lab06 get pod tracking-api-legacy \
  -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}'
```

```
ReplicaSet/tracking-api
```

**2. Three Pods answer the selector, one of which the ReplicaSet did not create**

```bash
kubectl -n kcna-lab06 get pods -l app=tracking-api -L provenance
```

```
NAME                  READY   STATUS    RESTARTS   AGE   PROVENANCE
tracking-api-4m2ql    1/1     Running   0          8m    replicaset
tracking-api-legacy   1/1     Running   0          9m    hand-created
tracking-api-x7ntb    1/1     Running   0          8m    replicaset
```

**3. The audit Pod's reading of the dataset**

```bash
kubectl -n kcna-lab06 logs label-audit
```

```
== MFS service inventory: tier=edge services ==
Container Tracking API app=tracking-api tier=edge env=staging release=r24
Customs Declaration Gateway app=customs-gateway tier=edge env=staging release=r24
Driver Mobile Backend app=driver-backend tier=edge env=staging release=r24
== counts by tier ==
edge=3
experimental=2
internal=5
AUDIT-COMPLETE
```

**4. The failure injection produced the real admission error**

```
The ReplicaSet "cargo-manifest-broken" is invalid: spec.template.metadata.labels: Invalid value: map[string]string{"app":"cargo-manifest", "env":"staging", "release":"r24", "tier":"internal"}: `selector` does not match template `labels`
```

## Notes on variance

* Pod name suffixes (`-4m2ql`, `-x7ntb`) are random on every run — never assert on them.
* `AGE` columns will differ.
* If Step 6 (orphaning) is left in its intermediate state, the adoption check reports the alternative `PASS` line *"tracking-api-legacy has no ownerReferences - it was orphaned by the relabel step"*. Re-apply the `tier=edge` label to return to the primary state.
