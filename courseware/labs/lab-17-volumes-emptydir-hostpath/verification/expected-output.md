# Lab 17 — expected output

Reference transcript for **Lab 17 · Volumes: emptyDir, hostPath and the Container Filesystem**, namespace `kcna-lab17`.

> **How to read this file.** Timestamps, Pod IPs, Pod UIDs, container IDs, node names and disk sizes are environment-specific and **will differ on your cluster**. Everything else — object names, statuses, counts, field values and error strings — should match exactly. Where a value is expected to vary it is called out inline.

---

## Step 1 — namespace

```
$ kubectl apply -f manifests/00-namespace.yaml
namespace/kcna-lab17 created

$ kubectl config view --minify -o jsonpath='{..namespace}{"\n"}'
kcna-lab17
```

## Step 2 — seed dataset

```
$ echo $(( $(wc -l < data/shipments.csv) - 1 ))
24

$ kubectl -n kcna-lab17 create configmap tracklane-seed --from-file=shipments.csv=data/shipments.csv
configmap/tracklane-seed created
```

## Step 3 — ephemerality proof

First run:

```
$ kubectl -n kcna-lab17 exec lane-scratch -- cat /tmp/tracklane/notes.txt
scratch-note written at 2026-09-05T04:11:23Z          <-- your timestamp will differ
```

After `delete` + re-`apply`:

```
$ kubectl -n kcna-lab17 exec lane-scratch -- cat /tmp/tracklane/notes.txt
scratch-note written at 2026-09-05T04:12:57Z          <-- LATER than the first; this is the point
```

The `containerID` changes between the two runs. **What must be true:** the second timestamp is strictly later than the first, and the two container IDs differ.

## Step 5 — emptyDir shared between containers

```
$ kubectl -n kcna-lab17 get pod lane-report -o wide
NAME          READY   STATUS    RESTARTS   AGE   IP            NODE                 NOMINATED NODE   READINESS GATES
lane-report   2/2     Running   0          18s   10.244.0.31   kcna-control-plane   <none>           <none>
```

`READY` must be `2/2`. IP and node name vary.

```
$ kubectl -n kcna-lab17 logs lane-report -c report-builder | head -1
report written to /shared/index.html (24 source rows)
```

The `24` is derived from `data/shipments.csv` and must match `wc -l data/shipments.csv` minus one.

```
$ kubectl -n kcna-lab17 exec lane-report -c report-web -- cat /shared/index.html
<h1>TrackLane depot report</h1>
<p>built: 2026-09-05T04:15:02Z</p>
<p>pod: lane-report</p>
<p>rows: 24</p>
<p>in_transit: 7</p>
<p>held_customs: 2</p>
```

`rows: 24`, `in_transit: 7` and `held_customs: 2` are fixed by the dataset and must match exactly.

Read-only enforcement in the web container:

```
$ kubectl -n kcna-lab17 exec lane-report -c report-web -- sh -c 'touch /shared/tamper 2>&1 || echo "write refused (expected)"'
touch: /shared/tamper: Read-only file system
write refused (expected)
```

Disk-backed emptyDir reports the node filesystem, **not** `sizeLimit`:

```
$ kubectl -n kcna-lab17 exec lane-report -c report-builder -- df -h /shared
Filesystem                Size      Used Available Use% Mounted on
overlay                  58.4G     21.7G     33.7G  39% /shared
```

Sizes vary; the filesystem name must **not** be `tmpfs`.

## Step 7 — memory-backed emptyDir

```
$ kubectl -n kcna-lab17 logs lane-cache
--- mount type for /cache ---
tmpfs on /cache type tmpfs (rw,relatime,size=32768k,inode64)
--- df for /cache ---
Filesystem                Size      Used Available Use% Mounted on
tmpfs                    32.0M         0     32.0M   0% /cache
```

`size=32768k` / `32.0M` is exactly the declared `sizeLimit: 32Mi`. Mount option ordering may differ between kernels; `type tmpfs` and the size must be present.

## Step 9 — hostPath read-only

```
$ kubectl -n kcna-lab17 logs node-log-peek
--- top level of the node's /var/log (read-only) ---
containers
journal
kubelet.log
kube-apiserver.log
kube-controller-manager.log
kube-scheduler.log
pods
--- can we write to it? ---
read-only mount refused the write (expected)
```

The exact directory listing depends on the node image; `containers` and `pods` are always present on a kind control-plane node. The final line **must** be `read-only mount refused the write (expected)` — if it says `WRITABLE` the `readOnly: true` mount flag was lost and the lab must be re-applied from `manifests/04-hostpath-node-logs.yaml`.

---

## Graded checks

```
$ bash verification/checks.sh
== Lab 17 verification — namespace kcna-lab17 ==
[PASS] namespace kcna-lab17 exists
[PASS] configmap tracklane-seed carries 25 lines of seed data
[PASS] pod/lane-report is Running with 2/2 containers ready
[PASS] emptyDir volume 'report' is declared on pod/lane-report
[PASS] report-builder and report-web both mount the 'report' volume
[PASS] /shared/index.html reports 24 rows (matches data/shipments.csv)
[PASS] report-web sees the file written by report-builder (cross-container share)
[PASS] pod/lane-cache mounts a Memory-medium emptyDir with sizeLimit 32Mi
[PASS] /cache is a tmpfs sized 32.0M
[PASS] pod/node-log-peek mounts hostPath /var/log with type Directory
[PASS] the hostPath mount is readOnly
[PASS] no container in kcna-lab17 requests privileged: true
------------------------------------------------
12 passed, 0 failed
```

Exit code `0`. Any `[FAIL]` line names the object and the observed value; re-read the corresponding step.

---

## Failure injection A — hostPath type assertion

```
$ kubectl -n kcna-lab17 get pod archive-writer-broken
NAME                    READY   STATUS              RESTARTS   AGE
archive-writer-broken   0/1     ContainerCreating   0          22s

$ kubectl -n kcna-lab17 describe pod archive-writer-broken | tail -12
Events:
  Type     Reason       Age                From               Message
  ----     ------       ----               ----               -------
  Normal   Scheduled    24s                default-scheduler  Successfully assigned kcna-lab17/archive-writer-broken to kcna-control-plane
  Warning  FailedMount  8s (x7 over 24s)   kubelet            MountVolume.SetUp failed for volume "archive" : hostPath type check failed: /mnt/tracklane-archive is not a directory
```

**Required signal:** `Scheduled` = Normal, `FailedMount` = Warning, and the literal substring `hostPath type check failed`. The retry count `(x7 over 24s)` grows the longer you wait.

## Failure injection B — tmpfs ENOSPC

```
$ kubectl -n kcna-lab17 exec lane-cache -- sh -c 'dd if=/dev/zero of=/cache/blob bs=1M count=40'
dd: error writing '/cache/blob': No space left on device
32+0 records in
31+0 records out
33554432 bytes (32.0MB) copied, 0.041826 seconds, 765.2MB/s
command terminated with exit code 1
```

**Required signal:** `No space left on device` and `33554432 bytes` (= 32 MiB, the declared `sizeLimit`). Throughput and elapsed time vary. The Pod must remain `Running` — it is not OOMKilled, because the filesystem refused the write first.

---

## Cleanup

```
$ kubectl delete namespace kcna-lab17 --wait=true
namespace "kcna-lab17" deleted

$ kubectl get namespace kcna-lab17
Error from server (NotFound): namespaces "kcna-lab17" not found
```

No cluster-scoped object is created by this lab, so the namespace delete is complete.
