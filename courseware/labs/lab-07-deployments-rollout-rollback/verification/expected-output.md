# Lab 07 — Expected verification evidence

Run from the lab directory **after** the rollback in section 6b has completed:

```bash
bash verification/checks.sh
```

## Expected transcript

```
Lab 07 verification - namespace kcna-lab07

== Namespace and dataset
  [PASS] namespace kcna-lab07 is Active (= Active)
  [PASS] release plan read: r24.2 wants replicas=4 surge=1 unavailable=0 (ceiling 5 / floor 4)

== Deployment shape matches the release plan
  [PASS] strategy type (= RollingUpdate)
  [PASS] spec.replicas (= 4)
  [PASS] maxSurge (= 1)
  [PASS] maxUnavailable (= 0)
  [PASS] revisionHistoryLimit (= 3)

== Rollback landed on the good release (r24.2)
  [PASS] current image (= nginx:1.27-alpine)
  [PASS] template release label (= r24.2)
  [PASS] mounted ConfigMap (= portal-site-r24-2)

== Availability
  [PASS] readyReplicas (= 4)
  [PASS] availableReplicas (= 4)
  [PASS] updatedReplicas (= 4)
  [PASS] Progressing condition reason (= NewReplicaSetAvailable)

== Served content comes from data/site-r24.2.html
  [PASS] page served by a live Pod (= RELEASE=r24.2)

== ReplicaSet generations retained
  [PASS] between 2 and 4 ReplicaSets retained under revisionHistoryLimit=3 (found 3)
  [PASS] exactly one ReplicaSet is scaled above zero (= 1)

== Service front door
  [PASS] Service type (= ClusterIP)
  [PASS] EndpointSlice backend addresses (= 4)

----------------------------------------
Lab 07: 19 passed, 0 failed
ALL CHECKS PASSED
```

```bash
echo $?
```

```
0
```

## Supporting evidence the learner should be able to produce

**1. The rollout obeyed its ceiling and floor**

Captured from the `--watch` in Step 4. `TOTAL` never exceeded `replicas + maxSurge = 5`; `AVAILABLE` never fell below `replicas - maxUnavailable = 4`.

```
DESIRED   UPDATED   TOTAL   AVAILABLE
4         4         4       4
4         1         5       4
4         2         5       4
4         3         5       4
4         4         5       4
4         4         4       4
```

**2. The wedged rollout stayed available**

```bash
kubectl -n kcna-lab07 get deploy freight-portal \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} reason={.reason}{"\n"}{end}'
```

```
Available=True reason=MinimumReplicasAvailable
Progressing=False reason=ProgressDeadlineExceeded
```

with

```
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
freight-portal   4/4     1            4           9m
```

**3. The real image-pull error**

```
Warning  Failed  41s (x4 over 2m11s)  kubelet  Failed to pull image "nginx:1.27-alpine-mfs-hotfix": failed to pull and unpack image "docker.io/library/nginx:1.27-alpine-mfs-hotfix": failed to resolve reference "docker.io/library/nginx:1.27-alpine-mfs-hotfix": docker.io/library/nginx:1.27-alpine-mfs-hotfix: not found
```

**4. History after the rollback — revision 2 became revision 4**

```bash
kubectl -n kcna-lab07 rollout history deployment/freight-portal
```

```
deployment.apps/freight-portal
REVISION  CHANGE-CAUSE
1         r24.1 - initial portal release
3         r24.3 - BROKEN image tag (deliberate)
4         r24.2 - customs banner, zero-unavailable rollout
```

**5. The immutable-selector rejection**

```
The Deployment "freight-portal" is invalid: spec.selector: Invalid value: v1.LabelSelector{MatchLabels:map[string]string{"app":"freight-portal", "tier":"frontend"}, MatchExpressions:[]v1.LabelSelectorRequirement(nil)}: field is immutable
```

## Notes on variance

* ReplicaSet name suffixes are `pod-template-hash` values and differ on every cluster — never assert on them.
* Running `checks.sh` **before** the rollback (while revision 3 is wedged) will fail `current image`, `template release label`, `updatedReplicas` and `Progressing condition reason`. That is the intended signal, not a script defect.
* `RS retained` accepts 2–4 because a learner who skips the r24.3 failure injection will have only two ReplicaSets.
