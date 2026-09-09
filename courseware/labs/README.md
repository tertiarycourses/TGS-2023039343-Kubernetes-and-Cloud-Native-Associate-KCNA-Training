# Kubernetes and Cloud Native Associate (KCNA) Training — Labs

**Course code:** TGS-2023039343 · **Version:** v6.1

Each folder contains its detailed guide, mock data, Kubernetes manifests and a verification script. Start with Lab 01 and the Learner Guide for workstation setup. The guide in each folder lists its own prerequisites and expected evidence.

Use the [Killercoda Kubernetes Playground](https://killercoda.com/playgrounds/scenario/kubernetes) as the recommended browser-based cluster. Clone the public learner repository in its terminal, enter `courseware/labs`, then open the assigned lab folder. For advanced exercises that require extra cluster components or a longer-lived session, follow the lab-specific local `kind` fallback in the Learner Guide.

## Day 1 — Cloud Native Foundations & Kubernetes Core Concepts

- [Lab 01 — Cluster Reconnaissance with kubectl](lab-01-kubectl-and-cluster-recon/README.md)
- [Lab 02 — Authoring Your First Pod Manifest](lab-02-first-pod-manifest/README.md)
- [Lab 03 — Commands, Arguments and Environment](lab-03-commands-args-env/README.md)
- [Lab 04 — Multi-Container Pod Patterns: Sidecar, Adapter, Ambassador](lab-04-multi-container-patterns/README.md)
- [Lab 05 — Container Images, OCI and the Runtime Interface](lab-05-container-images-oci/README.md)

## Day 2 — Workloads, Scheduling & Container Orchestration

- [Lab 06 — Labels, Selectors and ReplicaSets](lab-06-labels-selectors-replicasets/README.md)
- [Lab 07 — Deployments, Rollout Strategy and Rollback](lab-07-deployments-rollout-rollback/README.md)
- [Lab 08 — DaemonSets, Jobs and CronJobs](lab-08-daemonsets-jobs-cronjobs/README.md)
- [Lab 09 — Scheduling: nodeSelector, Affinity, Taints and Tolerations](lab-09-scheduling-affinity-taints/README.md)
- [Lab 10 — Resource Requests, Limits, QoS and Autoscaling](lab-10-resources-requests-limits-autoscaling/README.md)

## Day 3 — Services, Networking & Cluster Security

- [Lab 11 — Services, Endpoints and Cluster DNS](lab-11-services-endpoints/README.md)
- [Lab 12 — Service Types: ClusterIP, NodePort and LoadBalancer](lab-12-service-types-nodeport-lb/README.md)
- [Lab 13 — Ingress Resources and HTTP Routing](lab-13-ingress-routing/README.md)
- [Lab 14 — Namespaces, ServiceAccounts and RBAC](lab-14-namespaces-serviceaccounts-rbac/README.md)
- [Lab 15 — Secrets, ConfigMaps and Safe Injection](lab-15-secrets-configmaps/README.md)
- [Lab 16 — NetworkPolicy and Default-Deny Isolation](lab-16-networkpolicy-isolation/README.md)

## Day 4 — Storage, Cluster Architecture & Application Delivery

- [Lab 17 — Volumes: emptyDir, hostPath and the Container Filesystem](lab-17-volumes-emptydir-hostpath/README.md)
- [Lab 18 — PersistentVolumes, Claims and StorageClasses](lab-18-pv-pvc-storageclass/README.md)
- [Lab 19 — StatefulSets, Headless Services and Stable Identity](lab-19-statefulset-headless/README.md)
- [Lab 20 — Control Plane Anatomy and etcd Backup/Restore](lab-20-cluster-architecture-etcd/README.md)
- [Lab 21 — Packaging and Delivery: Helm, Kustomize and GitOps](lab-21-helm-kustomize-gitops/README.md)

## Day 5 — Observability, Troubleshooting & Assessment

- [Lab 22 — Probes, Health and Self-Healing](lab-22-probes-health-selfhealing/README.md)
- [Lab 23 — Events, Logs, Field Selectors and the Metrics Server](lab-23-events-logs-metrics/README.md)
- [Lab 24 — Metrics, Prometheus Exposition and the Observability Pipeline](lab-24-prometheus-observability/README.md)
- [Lab 25 — Troubleshooting Triage: Application, Node and Control Plane](lab-25-troubleshooting-triage/README.md)

Some advanced exercises use additional components. Lab 13 supplies a pinned Ingress controller path, Lab 16 supplies a policy-enforcing cluster path, and Lab 21 explains the tools needed to render Helm and Kustomize packages. Follow those lab-specific instructions before running the related checks.
