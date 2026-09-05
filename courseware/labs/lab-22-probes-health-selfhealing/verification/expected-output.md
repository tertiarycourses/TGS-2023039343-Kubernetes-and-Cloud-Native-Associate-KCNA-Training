# Lab 22 — Expected verification output

Run from the lab directory:

```bash
bash verification/checks.sh
```

## Honesty note

`checks.sh` is **read-only**: it creates, patches and deletes nothing. It is a
live check — it queries your cluster with `kubectl`, so it can only pass after
you have actually worked through the procedure in `README.md`.

The transcript below is the **shape** of a fully passing run. Counts of ready
replicas and endpoint addresses depend on how far through the lab you are.

## Fully passing run

```text
== Namespace isolation
  PASS  namespace kcna-lab22 exists
  PASS  Pod Security Admission enforce=baseline

== Part 1 — content ConfigMap sourced from data/
  PASS  configmap/depot-portal-content exists
  PASS  configmap key 'index.html' is populated
  PASS  configmap key 'ready.html' is populated

== Part 2 — depot-portal probes
  PASS  deployment/depot-portal exists
  PASS  readinessProbe configured (path=/ready.html)
  PASS  livenessProbe configured (path=/index.html)
  PASS  readiness and liveness target DIFFERENT paths (/ready.html vs /index.html)
  PASS  container image is pinned (nginx:1.27-alpine)
  PASS  depot-portal has 2 ready replica(s)

== Part 3 — Service backends via EndpointSlice
  PASS  service/depot-portal exists
  PASS  EndpointSlice carries 2 backend address(es)

== Part 4 — manifest-indexer startup probe
  PASS  deployment/manifest-indexer exists
  PASS  startupProbe present (failureThreshold=24 x periodSeconds=5s = 120s budget)
  PASS  startup budget 120s exceeds the app's ~40s boot time
  PASS  manifest-indexer reached Ready with 0 restarts

== Part 6 — failure injection cleaned up
  PASS  injected deployment manifest-indexer-outage removed

== Worksheet
  PASS  worksheet present at data/probe-tuning-worksheet.csv
  PASS  worksheet header intact

== Blast-radius guard
  PASS  no lab-22 objects in kube-system

SUMMARY: 18 passed, 0 failed
```

Exit code `0`.

## Common partial runs and what they mean

### You ran the checks before Part 4

```text
== Part 4 — manifest-indexer startup probe
  FAIL  deployment/manifest-indexer missing — see Step 4.1

SUMMARY: 14 passed, 1 failed
```

Exit code `1`. Apply `manifests/20-manifest-indexer-startup.yaml` and re-run.

### You ran the checks during Part 6, before cleanup

```text
== Part 6 — failure injection cleaned up
  FAIL  manifest-indexer-outage still present — see Step 6.10

SUMMARY: 17 passed, 1 failed
```

This is expected mid-lab. Complete Step 6.10 and re-run.

### You ran the checks in the 40-second startup window

```text
  FAIL  depot-portal has no ready replicas yet — wait, then re-run
```

Not a defect — you are inside the probe's grace window. Wait ~45 seconds and
re-run. If it never clears, work through the Troubleshooting table in
`README.md`.

## Manual observations the script cannot make for you

The script can confirm configuration and end state. It **cannot** confirm that
you watched the transition happen, which is the actual learning objective.
Before you sign off, be sure you personally observed all four:

| # | Observation | Where |
|---|---|---|
| 1 | An address **leaving** the EndpointSlice within ~13 s of deleting `ready.html` | Step 3.7 |
| 2 | `RESTARTS` remaining at **0** while the Pod was `0/1` | Step 3.8 |
| 3 | Five consecutive successful requests through the degraded Deployment | Step 3.10 |
| 4 | `Killing ... failed liveness probe, will be restarted` in the injected Deployment's events | Step 6.4 |
