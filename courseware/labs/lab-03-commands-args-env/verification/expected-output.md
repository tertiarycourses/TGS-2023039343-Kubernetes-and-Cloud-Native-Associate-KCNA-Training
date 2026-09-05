# Lab 03 — Expected evidence

Patch versions, node names, IPs and ages will differ. The **marker strings** are
the evidence.

---

## 1. ConfigMaps built from `data/`

```console
$ kubectl -n kcna-lab03 create configmap route-defaults --from-env-file=data/route-defaults.env
configmap/route-defaults created

$ kubectl -n kcna-lab03 get configmap route-defaults -o yaml
apiVersion: v1
data:
  BOOKING_API_HOST: booking.depot-portal.svc.cluster.local
  BOOKING_API_PORT: "8080"
  BOOKING_WINDOW_MINUTES: "45"
  COLD_CHAIN_REQUIRED: "true"
  CURRENCY: SGD
  DEPOT_CODE: MF-SIN-02
  DEPOT_REGION: sg-west
  LOG_LEVEL: info
  MAX_TRAILERS_PER_BAY: "3"
kind: ConfigMap
metadata:
  name: route-defaults
  namespace: kcna-lab03
```

Nine keys — one per non-comment line of `data/route-defaults.env`. The `#`
comment lines were dropped by `--from-env-file`.

```console
$ kubectl -n kcna-lab03 create configmap tariff-rates --from-file=data/tariff-rates.json
configmap/tariff-rates created
```

## 2. ENTRYPOINT / CMD override matrix

```console
$ kubectl -n kcna-lab03 get pods -l kcna.tertiaryinfotech.com/lab=lab-03
NAME                   READY   STATUS      RESTARTS   AGE
em-a-image-defaults    1/1     Running     0          31s
em-b-args-only         0/1     Completed   0          31s
em-c-command-override  0/1     Completed   0          31s
```

### A — no `command`, no `args`

```console
$ kubectl -n kcna-lab03 logs em-a-image-defaults | head -n 5
/docker-entrypoint.sh: /docker-entrypoint.d/ is not empty, will attempt to perform configuration
/docker-entrypoint.sh: Looking for shell scripts in /docker-entrypoint.d/
/docker-entrypoint.sh: Launching /docker-entrypoint.d/10-listen-on-ipv6-by-default.sh
10-listen-on-ipv6-by-default.sh: info: Getting the checksum of /etc/nginx/conf.d/default.conf
10-listen-on-ipv6-by-default.sh: info: Enabled listen on IPv6 in /etc/nginx/conf.d/default.conf
```

### B — `args` only: ENTRYPOINT kept, CMD replaced

```console
$ kubectl -n kcna-lab03 logs em-b-args-only
/docker-entrypoint.sh: /docker-entrypoint.d/ is not empty, will attempt to perform configuration
/docker-entrypoint.sh: Looking for shell scripts in /docker-entrypoint.d/
/docker-entrypoint.sh: Launching /docker-entrypoint.d/10-listen-on-ipv6-by-default.sh
10-listen-on-ipv6-by-default.sh: info: Getting the checksum of /etc/nginx/conf.d/default.conf
10-listen-on-ipv6-by-default.sh: info: Enabled listen on IPv6 in /etc/nginx/conf.d/default.conf
/docker-entrypoint.sh: Sourcing /docker-entrypoint.d/15-local-resolvers.envsh
/docker-entrypoint.sh: Launching /docker-entrypoint.d/20-envsubst-on-templates.sh
/docker-entrypoint.sh: Launching /docker-entrypoint.d/30-tune-worker-processes.sh
/docker-entrypoint.sh: Configuration complete; ready for start up
nginx version: nginx/1.27.5
```

The banner proves the ENTRYPOINT ran; `nginx version:` (instead of nginx serving
traffic) proves the CMD was replaced.

### C — `command` set: both discarded

```console
$ kubectl -n kcna-lab03 logs em-c-command-override
case C: image ENTRYPOINT was replaced by spec.command
case C: pid 1 is now: /bin/sh -c echo "case C: image ENTRYPOINT was replaced by spec.command" ...
case C: no /docker-entrypoint.sh banner above == proof
```

No banner. That absence is the whole point.

## 3. booking-config

```console
$ kubectl -n kcna-lab03 logs booking-config
=== 1. envFrom: every key of ConfigMap route-defaults ===
DEPOT_REGION=sg-west
DEPOT_CODE=MF-SIN-02
BOOKING_WINDOW_MINUTES=45
CURRENCY=SGD
LOG_LEVEL=info
=== 2. envFrom with prefix: MF_ ===
MF_DEPOT_CODE=MF-SIN-02
=== 3. explicit env, incl. downward API ===
SERVICE_NAME=booking
POD_NAME=booking-config
NODE_NAME=kcna-qa-20260905-control-plane
MEM_LIMIT_MI=64
=== 4. dependent env var expanded by the kubelet ===
BOOKING_ENDPOINT=http://booking.kcna-lab03.svc.cluster.local:8080
=== 5. dataset mounted from ConfigMap tariff-rates ===
TARIFF_TABLE=/etc/depot/tariff-rates.json
tariff entries: 10
rate row for MF-SIN-02:
    { "depot_code": "MF-SIN-02", "bay_hour": 51.00, "cold_chain_surcharge": 21.50, "after_hours_multiplier": 1.40 },
=== booking-config ready ===
```

Full environment as the process actually sees it:

```console
$ kubectl -n kcna-lab03 exec booking-config -- env | sort | head -n 16
BOOKING_API_HOST=booking.depot-portal.svc.cluster.local
BOOKING_API_PORT=8080
BOOKING_ENDPOINT=http://booking.kcna-lab03.svc.cluster.local:8080
BOOKING_WINDOW_MINUTES=45
COLD_CHAIN_REQUIRED=true
CURRENCY=SGD
DEPOT_CODE=MF-SIN-02
DEPOT_REGION=sg-west
HOME=/
HOSTNAME=booking-config
LOG_LEVEL=info
MAX_TRAILERS_PER_BAY=3
MEM_LIMIT_MI=64
MF_BOOKING_API_HOST=booking.depot-portal.svc.cluster.local
MF_BOOKING_API_PORT=8080
MF_BOOKING_WINDOW_MINUTES=45
```

## 4. Failure injection — CrashLoopBackOff

```console
$ kubectl -n kcna-lab03 get pod booking-missing-env
NAME                  READY   STATUS             RESTARTS      AGE
booking-missing-env   0/1     CrashLoopBackOff   3 (28s ago)   72s
```

```console
$ kubectl -n kcna-lab03 logs booking-missing-env
Error from server (BadRequest): container "app" in pod "booking-missing-env" is waiting to start: CrashLoopBackOff
```

```console
$ kubectl -n kcna-lab03 logs booking-missing-env --previous
[preflight] booking-api starting
[preflight] FATAL: TARIFF_TABLE is not set - refusing to start
```

```console
$ kubectl -n kcna-lab03 get pod booking-missing-env \
    -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}'
1
```

```console
$ kubectl -n kcna-lab03 describe pod booking-missing-env | sed -n '/Last State/,/Ready/p'
    Last State:     Terminated
      Reason:       Error
      Exit Code:    1
      Started:      Sat, 05 Sep 2026 16:03:11 +0800
      Finished:     Sat, 05 Sep 2026 16:03:11 +0800
    Ready:          False
```

## 5. Verification script

```console
$ bash verification/checks.sh

== 0. Cluster reachability
  [PASS] kubectl can reach the API server

== 1. Namespace and ConfigMaps built from data/
  [PASS] namespace kcna-lab03 exists
  [PASS] ConfigMap route-defaults has 9 keys, matching data/route-defaults.env
  [PASS] ConfigMap tariff-rates carries data/tariff-rates.json

== 2. ENTRYPOINT / CMD override matrix
  [PASS] A (no command/args): nginx runs from the image ENTRYPOINT + CMD
  [PASS] B (args only): the image ENTRYPOINT still ran
  [PASS] B (args only): image CMD was replaced by args ['nginx','-v']
  [PASS] C (command set): spec.command ran instead of the image ENTRYPOINT
  [PASS] C (command set): no ENTRYPOINT banner, so ENTRYPOINT and CMD were both discarded

== 3. booking-config Pod: env, envFrom and downward API
  [PASS] Pod booking-config phase is Running
  [PASS] log contains 'DEPOT_REGION=sg-west'
  [PASS] log contains 'DEPOT_CODE=MF-SIN-02'
  [PASS] log contains 'MF_DEPOT_CODE=MF-SIN-02'
  [PASS] log contains 'BOOKING_ENDPOINT=http://booking.kcna-lab03.svc.cluster.local:8080'
  [PASS] log contains 'MEM_LIMIT_MI=64'
  [PASS] log contains 'tariff entries: 10'
  [PASS] log contains 'booking-config ready'
  [PASS] downward API injected NODE_NAME
  [PASS] the missing ConfigMap route-overrides is referenced with optional: true

== 4. Failure injection: CrashLoopBackOff evidence
  [PASS] booking-missing-env is in CrashLoopBackOff as designed
  [PASS] lastState.terminated.exitCode is 1 (the preflight refused to start)
  [PASS] restartCount is 3 (>=1)
  [PASS] kubectl logs --previous shows the FATAL preflight message

Result: 23 passed, 0 failed
```
