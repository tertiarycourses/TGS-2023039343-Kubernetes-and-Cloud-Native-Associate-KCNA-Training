# Lab 11 — Expected output reference

All Pod IPs, ClusterIPs, ReplicaSet hashes, EndpointSlice name suffixes and ages are
allocated at runtime and **will differ on your cluster**. Compare the *shape* and the
*relationships* between values, not the literal digits.

---

## `bash verification/checks.sh` — clean run

```
== Lab 11 verification: Services, Endpoints and Cluster DNS ==
PASS  namespace kcna-lab11 exists
PASS  ConfigMap quote-api-content matches data/quote-api-index.html byte-for-byte
PASS  deployment quote-api has 3/3 ready replicas
PASS  service quote-api is ClusterIP with port 80
PASS  service quote-api targetPort is the named port "http"
PASS  EndpointSlice resolved the named port to 8080
PASS  EndpointSlice holds 3 ready addresses
PASS  EndpointSlice addresses match the quote-api Pod IPs exactly
PASS  dns fixture: quote-api resolves
PASS  dns fixture: quote-api.kcna-lab11 resolves
PASS  dns fixture: quote-api.kcna-lab11.svc resolves
PASS  dns fixture: quote-api.kcna-lab11.svc.cluster.local resolves
PASS  dns fixture: quote-api.default.svc.cluster.local correctly does NOT resolve
PASS  dns fixture: kubernetes.default.svc.cluster.local resolves
PASS  HTTP GET through the Service returns the Meridian Freight page
-- 15 passed, 0 failed --
```

Exit status `0`. Any `FAIL` line prints the expected and observed values inline.

---

## Key intermediate outputs

### The Service (Step 4)

```
NAME        TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
quote-api   ClusterIP   10.96.114.23    <none>        80/TCP    6s
```

`EXTERNAL-IP` is `<none>` and stays `<none>`. A ClusterIP Service is reachable **only
from inside the cluster** — that is not a defect.

### The EndpointSlice (Step 5)

```
NAME              ADDRESSTYPE   PORTS   ENDPOINTS                             AGE
quote-api-t8hkb   IPv4          8080    10.244.0.14,10.244.0.15,10.244.0.16   45s
```

The two load-bearing facts:

| Column | Value | Why it matters |
|---|---|---|
| `PORTS` | `8080` | The Service says `targetPort: http`; the slice records the **resolved number**. If this said `<unset>`, the named port did not resolve. |
| `ENDPOINTS` | three Pod IPs | Identical set to `kubectl get pods -l app=quote-api -o wide`. If this is empty, the selector matched nothing. |

Per-endpoint detail:

```
10.244.0.14	true	quote-api-6c9b4f7d55-7lqm2
10.244.0.15	true	quote-api-6c9b4f7d55-jd8vx
10.244.0.16	true	quote-api-6c9b4f7d55-x2t9k
```

Column 2 is `conditions.ready`. Only `true` endpoints receive traffic.

### Resolver configuration (Step 6)

```
search kcna-lab11.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
```

`10.96.0.10` is the `kube-dns` Service ClusterIP in `kube-system`; on a default kind
cluster it is the tenth address of the service CIDR.

### DNS answer (Step 7)

```
Server:		10.96.0.10
Address:	10.96.0.10:53


Name:	quote-api.kcna-lab11.svc.cluster.local
Address: 10.96.114.23

```

**Known BusyBox behaviour — two separate artefacts, both observed:**

1. `busybox:1.36` also issues an AAAA query. On an IPv4-only kind cluster you may
   additionally see `*** Can't find …: No answer` and a non-zero exit code, *even for a
   name that resolved correctly over IPv4*.
2. **BusyBox `nslookup` does not apply the `search` list to a name that already
   contains a dot.** `nslookup quote-api.kcna-lab11` and
   `nslookup quote-api.kcna-lab11.svc` therefore report `No answer` on a cluster where
   those names resolve perfectly for real clients, because `nslookup` never appends
   `svc.cluster.local` / `cluster.local`.

Neither is a Service fault. `verification/checks.sh` therefore resolves each fixture
with `ping -c 1 -W 1` and reads only the address in the `PING <name> (<ip>)` header —
`ping` uses the standard resolver and honours `/etc/resolv.conf`. ICMP replies are
ignored, because a ClusterIP is a kube-proxy DNAT rule and is under no obligation to
answer ping:

```
$ kubectl exec -n kcna-lab11 dns-client -- ping -c 1 -W 1 quote-api.kcna-lab11
PING quote-api.kcna-lab11 (10.96.114.23): 56 data bytes

--- quote-api.kcna-lab11 ping statistics ---
1 packets transmitted, 0 packets received, 100% packet loss
```

Resolution succeeded (address in parentheses); packet loss is expected and is not part
of the assertion. A name that genuinely does not resolve looks completely different:

```
$ kubectl exec -n kcna-lab11 dns-client -- ping -c 1 -W 1 quote-api.default.svc.cluster.local
ping: bad address 'quote-api.default.svc.cluster.local'
command terminated with exit code 1
```

### Cross-namespace negative (Step 7)

```
Server:		10.96.0.10
Address:	10.96.0.10:53

*** Can't find quote-api.default.svc.cluster.local: No answer

command terminated with exit code 1
```

This failure is **correct and expected**. A Service record only exists under its own
namespace.

---

## Failure-injection reference (Section 6)

Symptom:

```
wget: can't connect to remote host (10.96.203.77): Connection refused
command terminated with exit code 1
```

Empty slice:

```
NAME                     ADDRESSTYPE   PORTS   ENDPOINTS   AGE
quote-api-broken-4zq6n   IPv4          <unset> <unset>     40s
```

`kubectl describe service quote-api-broken` — the decisive two lines:

```
Selector:                 app=quote-apis
Endpoints:
```

Root-cause proof:

```
$ kubectl get pods -n kcna-lab11 -l app=quote-apis
No resources found in kcna-lab11 namespace.
```

After the patch, the slice repopulates without any Pod restart:

```
NAME                     ADDRESSTYPE   PORTS   ENDPOINTS                             AGE
quote-api-broken-4zq6n   IPv4          8080    10.244.0.14,10.244.0.15,10.244.0.16   2m5s
```

---

## Environment caveats recorded for this lab

| Caveat | Effect on this lab |
|---|---|
| `busybox:1.36` `nslookup` also queries AAAA | Extra `No answer` line and a non-zero exit for names that resolve fine over IPv4 |
| `busybox:1.36` `nslookup` ignores the `search` list for dotted partial names | `quote-api.kcna-lab11` and `quote-api.kcna-lab11.svc` report `No answer` under `nslookup` but resolve correctly under `ping`, `wget` and any normal application resolver. Checks use `ping`'s resolution line |
| A ClusterIP does not answer ICMP | `ping` shows `100% packet loss` for a healthy Service. Only the resolved address in the `PING <name> (<ip>)` header is meaningful |
| `v1 Endpoints` deprecated in Kubernetes v1.33 | `kubectl get endpoints` still works today but is not the API to build on; `endpointslices` is used throughout |
| kube-proxy in iptables mode REJECTs a ClusterIP with no endpoints | Produces *Connection refused* immediately. On a cluster in IPVS mode, or behind some CNIs, the same fault can present as a **timeout** instead |
| ClusterIP is cluster-internal only | Nothing in this lab is reachable from your laptop without `kubectl port-forward`; that is by design and is explored in Lab 12 |
