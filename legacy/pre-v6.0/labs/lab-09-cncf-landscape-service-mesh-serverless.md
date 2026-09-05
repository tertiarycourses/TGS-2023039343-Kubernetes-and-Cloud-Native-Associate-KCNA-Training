# Lab 09 - CNCF Landscape, Service Mesh, Serverless

## Objectives

- Navigate the CNCF landscape conceptually.
- Explain graduated, incubating, and sandbox projects.
- Describe service mesh use cases.
- Explain serverless and FaaS.
- Map cloud native tools to categories.

## Scenario

Your manager asks whether the team should adopt Kubernetes add-ons for networking, observability, delivery, and serverless. You need to explain the ecosystem without overwhelming the team.

## Steps

### 1. Review CNCF Project Maturity

Define Sandbox, Incubating, and Graduated. Explain why maturity matters when selecting tools.

### 2. Map Tool Categories

| Category | Example Tools |
| --- | --- |
| Container runtime | containerd, CRI-O |
| Networking | Cilium, Calico, Flannel |
| Observability | Prometheus, Grafana, Jaeger, OpenTelemetry |
| Service mesh | Istio, Linkerd |
| GitOps | Argo CD, Flux |
| Packaging | Helm |
| Serverless | Knative |

### 3. Explain Service Mesh

Document how service mesh can help with service-to-service traffic, mTLS, retries, timeouts, traffic splitting, and observability.

### 4. Explain Serverless

| Model | Description |
| --- | --- |
| Containers on Kubernetes | Team manages workloads on cluster |
| Serverless | Platform abstracts server management |
| FaaS | Function runs in response to events |

### 5. Choose Tools for a Scenario

For a small team, recommend one observability tool, one delivery tool, whether service mesh is needed immediately, and whether serverless fits event-driven jobs.

## Validation

You should have a CNCF maturity definition, category map, service mesh notes, serverless comparison, and tool recommendation.

## Checkpoint Questions

1. What is CNCF?
2. Why is Prometheus commonly associated with Kubernetes observability?
3. What problem does service mesh solve?
4. When is serverless attractive?

## Exam Focus

KCNA expects familiarity with common cloud native categories and examples, not deep implementation expertise.
