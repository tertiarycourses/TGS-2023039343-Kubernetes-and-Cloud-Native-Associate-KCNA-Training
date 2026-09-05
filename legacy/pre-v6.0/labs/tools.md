# Tools Guide

## Required Tools

| Tool | Purpose |
| --- | --- |
| kubectl | Command-line tool for interacting with Kubernetes clusters. |
| Minikube or Kind | Local Kubernetes cluster for practice. |
| Docker or compatible container runtime | Container runtime used by local lab tools. |
| Text editor | YAML manifests and notes. |
| Web browser | Documentation and CNCF landscape review. |

## Optional Tools

| Tool | Purpose |
| --- | --- |
| Helm | Package manager for Kubernetes applications. |
| Kubernetes Dashboard | Browser-based cluster inspection. |
| Prometheus | Metrics collection concept and optional lab tool. |
| Grafana | Metrics visualization concept and optional lab tool. |
| Argo CD or Flux | GitOps concepts and optional demo. |
| diagrams.net | Architecture and workflow diagrams. |

## Recommended Files

Create these during the course:

```text
kcna-lab-notes.md
kubernetes-objects-cheatsheet.md
kubectl-commands.md
cloud-native-glossary.md
exam-mistakes-log.md
```

## Cleanup Checklist

After labs, check:

```bash
kubectl get all -n kcna-lab
kubectl get configmap,secret,pvc -n kcna-lab
```

Delete unused resources:

```bash
kubectl delete all --all -n kcna-lab
```
