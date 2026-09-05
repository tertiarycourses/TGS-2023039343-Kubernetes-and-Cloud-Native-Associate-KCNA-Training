# Lab 08 — Expected verification evidence

Run from the lab directory. Run it **after** the failure injection (section 6) but **before** the fix, so the `BackoffLimitExceeded` assertions are exercised:

```bash
bash verification/checks.sh
```

## Expected transcript (single-node kind cluster)

```
Lab 08 verification - namespace kcna-lab08

== Namespace and datasets
  [PASS] namespace kcna-lab08 is Active (= Active)
  [PASS] datasets read: 8 berths (3 high-occupancy), 6 queue items, 2 tariff lanes under review
  [PASS] ConfigMap berth-data carries all three data files

== DaemonSet berth-agent (one Pod per node)
  [PASS] cluster has 1 schedulable node(s) - a DaemonSet must produce exactly that many Pods
  [PASS] desiredNumberScheduled equals the node count (= 1)
  [PASS] numberReady equals the node count (= 1)
  [PASS] a DaemonSet has no .spec.replicas field (= )
  [PASS] agent log reports the dataset it read (= berths=8 high_occupancy=3)

== Indexed Job manifest-reconcile
  [PASS] completionMode (= Indexed)
  [PASS] completions matches the queue length (= 6)
  [PASS] parallelism (= 2)
  [PASS] succeeded Pods (= 6)
  [PASS] Job condition Complete (= True)
  [PASS] one Pod per completion index (= 6)
  [PASS] distinct work items reported RECONCILED (= 6)

== CronJob tariff-sync
  [PASS] schedule (= */2 * * * *)
  [PASS] concurrencyPolicy (= Forbid)
  [PASS] successfulJobsHistoryLimit (= 3)
  [PASS] CronJob has spawned 2 Job(s), within successfulJobsHistoryLimit=3
  [PASS] a tariff-sync run printed SYNC-OK
  [PASS] tariff-sync flagged the lanes marked 'review' in tariff-rates.csv (>=2 lines, found 2)

== Failure injection: customs-export exceeded its backoffLimit
  [PASS] customs-export failure reason (= BackoffLimitExceeded)
  [PASS] failed Pod attempts (1 initial + backoffLimit 2) (= 3)

----------------------------------------
Lab 08: 23 passed, 0 failed
ALL CHECKS PASSED
```

```bash
echo $?
```

```
0
```

## Supporting evidence the learner should be able to produce

**1. The DaemonSet count is derived from the node set — one node, one Pod**

```bash
kubectl get nodes --no-headers | wc -l
kubectl -n kcna-lab08 get ds berth-agent \
  -o jsonpath='desired={.status.desiredNumberScheduled} ready={.status.numberReady}'
```

```
       1
desired=1 ready=1
```

There is no `.spec.replicas` to print:

```bash
kubectl -n kcna-lab08 get ds berth-agent -o jsonpath='{.spec.replicas}'; echo "<-- empty"
```

```
<-- empty
```

**2. The agent's reading of `data/berth-readings.csv` matches the file**

```bash
kubectl -n kcna-lab08 logs -l app=berth-agent --tail=1
awk -F, 'NR>1 && $5+0 >= 90 {print $2, $5"%"}' data/berth-readings.csv
```

```
02:14:47 node=kind-control-plane berths=8 high_occupancy=3
B01 92%
B03 96%
B06 90%
```

**3. Six indexes, six distinct work items, none repeated**

```bash
kubectl -n kcna-lab08 get job manifest-reconcile \
  -o jsonpath='completed={.status.completedIndexes} succeeded={.status.succeeded}'
kubectl -n kcna-lab08 logs -l job-name=manifest-reconcile --tail=-1 | grep -c RECONCILED
```

```
completed=0-5 succeeded=6
6
```

**4. The CronJob's reading of `data/tariff-rates.csv`**

```
tariff-sync run at 2026-09-05T02:20:03Z
lanes=8 mean_rate_sgd=683.66
FLAGGED SG-ID Singapore to Tanjung Priok
FLAGGED SG-AE Singapore to Jebel Ali
SYNC-OK
```

**5. The failure injection — three attempts, then the controller gives up**

```bash
kubectl -n kcna-lab08 describe job customs-export | sed -n '/^Events:/,$p'
```

```
Events:
  Type     Reason                Age    From            Message
  ----     ------                ----   ----            -------
  Normal   SuccessfulCreate      2m10s  job-controller  Created pod: customs-export-9wq4k
  Normal   SuccessfulCreate      2m     job-controller  Created pod: customs-export-cn2xr
  Normal   SuccessfulCreate      95s    job-controller  Created pod: customs-export-4tbvz
  Warning  BackoffLimitExceeded  89s    job-controller  Job has reached the specified backoff limit
```

with the application-level cause in the Pod log:

```
customs-export starting
wc: /data/customs-export.csv: No such file or directory
EXPORT-FAILED: source file missing
```

## Notes on variance

* **Node count.** The DaemonSet assertions compare against the live `kubectl get nodes` count, not a hard-coded `1`. On a 3-node kind cluster the same script passes with `desired=3`.
* **CronJob Job count.** `CronJob has spawned N Job(s)` accepts 1–3 depending on how long the lab has been running and whether `tariff-sync-manual` was created. Manually created Jobs also carry `app=tariff-sync` and are counted.
* If you run `checks.sh` **after** repairing the customs-export Job, the last block prints the single line *"customs-export Job not present - failure injection is optional, section 6 skipped"* only when the Job has been deleted; if the repaired Job exists and is `Complete`, the `Failed` condition is absent and the same optional-skip line is printed. Total pass count then drops to 22.
* Pod name random suffixes, timestamps and `AGE` columns always differ.
