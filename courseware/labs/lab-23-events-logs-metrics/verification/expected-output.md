# Lab 23 — Expected verification output

Run from the lab directory:

```bash
bash verification/checks.sh
```

## Honesty note

`checks.sh` is **read-only** and queries your live cluster. It **auto-detects**
whether you installed metrics-server (Part 5 **Path A**) or skipped it
(**Path B**).

**Path B is a valid completion of this lab.** Its metrics checks report `SKIP`,
not `FAIL`, and the script still exits `0`. A stock kind cluster has no
metrics-server, and pretending otherwise would be the exact dishonesty this lab
teaches you to avoid.

---

## Path B — metrics-server NOT installed (default on stock kind)

```text
== Namespace isolation
  PASS  namespace kcna-lab23 exists
  PASS  Pod Security Admission enforce=baseline

== Part 1 — access-log corpus loaded from data/
  PASS  configmap/depot-access-log exists
  PASS  corpus loaded (30 lines)
  PASS  corpus contains the ERROR/upstream_timeout records used in Part 4

== Part 2 — event-producing workloads
  PASS  deployment/depot-portal exists
  PASS  deployment/gate-scanner exists
  PASS  pod/depot-gate-agent exists (the FailedMount event source)
  PASS  depot-portal Pod has 2 containers (portal + audit-sidecar)

== Part 3 — Events and field selectors
  PASS  compound field selector returns 2 Warning event(s) about Pods
  PASS  reason=FailedMount selector returns the depot-gate-agent event
  PASS  non-indexed field selector is rejected server-side (expected)

== Part 4 — logs
  PASS  found depot-portal pod depot-portal-58d6c47f9b-rz8nq
  PASS  container 'portal' is emitting the data/ corpus to stdout
  PASS  container 'audit-sidecar' is shipping its file to stdout
  PASS  gate-scanner has restarted 4 time(s) — --previous is meaningful

== Part 5 — metrics pipeline (Path A or Path B)
  SKIP  metrics.k8s.io not installed — Path B. This is a VALID completion.
  SKIP  kubectl top checks not applicable on Path B
  PASS  kubectl top fails with the documented Path B error (expected on stock kind)

== Worksheet
  PASS  worksheet present at data/event-triage-worksheet.csv
  PASS  worksheet header intact

== Blast-radius guard
  PASS  no lab-23 workloads/config in kube-system
  SKIP  no kube-system RoleBinding (Path B, or already cleaned up)

SUMMARY: 18 passed, 0 failed, 4 skipped
```

Exit code `0`.

---

## Path A — metrics-server installed

The Part 5 and blast-radius blocks change to:

```text
== Part 5 — metrics pipeline (Path A or Path B)
  PASS  APIService v1beta1.metrics.k8s.io exists (Path A)
  PASS  aggregation layer reports Available=True
  PASS  --kubelet-insecure-tls present (required on kind; lab clusters only)
  PASS  metrics-server image is pinned (registry.k8s.io/metrics-server/metrics-server:v0.7.2)
  PASS  kubectl top pods returns data

== Blast-radius guard
  PASS  no lab-23 workloads/config in kube-system
  PASS  the one documented kube-system RoleBinding is present (Path A)

SUMMARY: 24 passed, 0 failed, 0 skipped
```

Exit code `0`.

> Note that the script asserts `kubectl top pods` **returns data** — it does not
> assert any particular millicore or byte value, because no such value can be
> predicted. See Step 5.6 in `README.md` for the one quantitative claim that
> *is* defensible: the `indexer` container is capped by a 100m CFS quota and
> must never be reported above it.

---

## Common partial runs

### Run too early, before events have accumulated

```text
== Part 3 — Events and field selectors
  FAIL  no Warning events yet — wait ~60s after Step 2.1, then re-run
```

Exit code `1`. Not a defect — `BackOff` needs a restart cycle and `FailedMount`
is re-raised on a timer. Wait 60 seconds and re-run.

### Path A, run inside the first scrape window

```text
  FAIL  kubectl top pods still failing — allow ~60s for the first scrape window
```

metrics-server needs at least one `--metric-resolution=15s` cycle after becoming
Ready. Wait and re-run. If it never clears, check
`kubectl logs -n kcna-lab23 deploy/metrics-server` against the Troubleshooting
table in `README.md`.

### Path A, RoleBinding not applied

```text
  FAIL  APIService Available='False' — see the Troubleshooting table
  SKIP  no kube-system RoleBinding (Path B, or already cleaned up)
```

metrics-server cannot read the `extension-apiserver-authentication` ConfigMap.
Either apply `manifests/91-metrics-server-kube-system-rolebinding.yaml` or
switch to Path B.

---

## Manual observations the script cannot make for you

| # | Observation | Where |
|---|---|---|
| 1 | Unsorted `kubectl get events` output is **not** chronological | Step 3.1 vs 3.2 |
| 2 | An event showing `(x2 over 3m1s)` — aggregation, not enumeration | Step 3.3 |
| 3 | `count`, `firstTimestamp` and `lastTimestamp` on the raw Event object | Step 3.8 |
| 4 | `--event-ttl` is **not** set by kubeadm, so the 1 hour default applies | Step 3.9 |
| 5 | `--previous` showing the FATAL line that the current container has not reached | Step 4.5 |
| 6 | The audit file existing inside the container and reaching `kubectl logs` **only** because a `tail -f` re-emits it | Step 4.7 |
| 7 | `kubectl logs` returning `NotFound` immediately after the Pod is deleted | Step 4.9 |
| 8 | The two *different* metrics failure strings: `Metrics API not available` vs `ServiceUnavailable` | Steps 5.1 and 6.2 |
