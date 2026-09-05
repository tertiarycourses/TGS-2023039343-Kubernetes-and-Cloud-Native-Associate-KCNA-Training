# Kubernetes and Cloud Native Associate (KCNA) Training

Build and explain Kubernetes solutions through practical labs covering cloud native architecture, workloads, networking, security, storage and observability.

| Course detail | Information |
|---|---|
| Course code | `TGS-2023039343` |
| Programme | WSQ |
| Duration | 5 days / 40 hours: 37 training + 3 assessment |
| Registration | [View course details and register](https://www.tertiarycourses.com.sg/wsq-kubernetes-and-cloud-native-associate-kcna-training.html) |
| Funding | Up to 70% for eligible learners. Eligibility and terms apply; see the registration page. |
| Courseware | v6.0 |

## About the course

Use Kubernetes manifests, mock business data and observable cluster behaviour to connect cloud native concepts with practical decisions. The course follows the registered Solution Architecture outcomes (`ICT-DES-4006-1.1`) and covers the current KCNA subject domains. KCNA certification is a separate Linux Foundation examination.

## Learning outcomes

- **LO1:** Develop a Kubernetes architectural proof of concept.
- **LO2:** Identify the technical and practical requirements in a Kubernetes setup.
- **LO3:** Develop a solution architecture within Kubernetes.
- **LO4:** Prepare a technical blueprint for a Kubernetes-based solution for security and storage.
- **LO5:** Demonstrate Kubernetes solution for a specific business problem.
- **LO6:** Implement regular monitoring of the Kubernetes system and perform necessary troubleshooting.

## Topics covered

- Core Concepts
- Workloads & Scheduling
- Services and Networking
- Security
- Storage
- Cluster Architecture, Installation & Configuration
- Logging and Monitoring
- Troubleshooting
- Cloud native principles and the CNCF ecosystem
- Container orchestration and OCI images
- CI/CD, Helm, Kustomize and GitOps

## Labs

Each lab has its own guide, mock data, Kubernetes YAML and verification script. Follow the detailed procedure in its README or the Learner Guide.

- [Lab 01 — Cluster Reconnaissance with kubectl](courseware/labs/lab-01-kubectl-and-cluster-recon/README.md)
- [Lab 02 — Authoring Your First Pod Manifest](courseware/labs/lab-02-first-pod-manifest/README.md)
- [Lab 03 — Commands, Arguments and Environment](courseware/labs/lab-03-commands-args-env/README.md)
- [Lab 04 — Multi-Container Pod Patterns: Sidecar, Adapter, Ambassador](courseware/labs/lab-04-multi-container-patterns/README.md)
- [Lab 05 — Container Images, OCI and the Runtime Interface](courseware/labs/lab-05-container-images-oci/README.md)
- [Lab 06 — Labels, Selectors and ReplicaSets](courseware/labs/lab-06-labels-selectors-replicasets/README.md)
- [Lab 07 — Deployments, Rollout Strategy and Rollback](courseware/labs/lab-07-deployments-rollout-rollback/README.md)
- [Lab 08 — DaemonSets, Jobs and CronJobs](courseware/labs/lab-08-daemonsets-jobs-cronjobs/README.md)
- [Lab 09 — Scheduling: nodeSelector, Affinity, Taints and Tolerations](courseware/labs/lab-09-scheduling-affinity-taints/README.md)
- [Lab 10 — Resource Requests, Limits, QoS and Autoscaling](courseware/labs/lab-10-resources-requests-limits-autoscaling/README.md)
- [Lab 11 — Services, Endpoints and Cluster DNS](courseware/labs/lab-11-services-endpoints/README.md)
- [Lab 12 — Service Types: ClusterIP, NodePort and LoadBalancer](courseware/labs/lab-12-service-types-nodeport-lb/README.md)
- [Lab 13 — Ingress Resources and HTTP Routing](courseware/labs/lab-13-ingress-routing/README.md)
- [Lab 14 — Namespaces, ServiceAccounts and RBAC](courseware/labs/lab-14-namespaces-serviceaccounts-rbac/README.md)
- [Lab 15 — Secrets, ConfigMaps and Safe Injection](courseware/labs/lab-15-secrets-configmaps/README.md)
- [Lab 16 — NetworkPolicy and Default-Deny Isolation](courseware/labs/lab-16-networkpolicy-isolation/README.md)
- [Lab 17 — Volumes: emptyDir, hostPath and the Container Filesystem](courseware/labs/lab-17-volumes-emptydir-hostpath/README.md)
- [Lab 18 — PersistentVolumes, Claims and StorageClasses](courseware/labs/lab-18-pv-pvc-storageclass/README.md)
- [Lab 19 — StatefulSets, Headless Services and Stable Identity](courseware/labs/lab-19-statefulset-headless/README.md)
- [Lab 20 — Control Plane Anatomy and etcd Backup/Restore](courseware/labs/lab-20-cluster-architecture-etcd/README.md)
- [Lab 21 — Packaging and Delivery: Helm, Kustomize and GitOps](courseware/labs/lab-21-helm-kustomize-gitops/README.md)
- [Lab 22 — Probes, Health and Self-Healing](courseware/labs/lab-22-probes-health-selfhealing/README.md)
- [Lab 23 — Events, Logs, Field Selectors and the Metrics Server](courseware/labs/lab-23-events-logs-metrics/README.md)
- [Lab 24 — Metrics, Prometheus Exposition and the Observability Pipeline](courseware/labs/lab-24-prometheus-observability/README.md)
- [Lab 25 — Troubleshooting Triage: Application, Node and Control Plane](courseware/labs/lab-25-troubleshooting-triage/README.md)

## Course materials

- [Learner Guide](courseware/LEARNER-GUIDE.md)
- [Learner Guide PDF](courseware/LG-Kubernetes%20and%20Cloud%20Native%20Associate%20%28KCNA%29%20Training-v6.0.pdf)
- [Learner slides PDF](courseware/Kubernetes%20and%20Cloud%20Native%20Associate%20%28KCNA%29%20Training-v6.0.pdf)
- [Earlier learner materials](legacy/pre-v6.0/) are retained for historical reference. Use the current labs above for this version.

## Using the labs

Start with Lab 01 for cluster and command-line prerequisites. Some optional exercises need extra controllers or a policy-capable cluster; their guides identify and supply the installation path. Read each lab's scope before applying its manifests. Mock data is synthetic and lab credentials are examples only.

## Distribution

This public repository contains learner materials. Assessments, answer keys, source reference books, private configuration and build/QA files are distributed separately through the appropriate course channels.

## Provider

Tertiary Infotech Academy Pte Ltd (Tertiary Courses). [Course details and registration](https://www.tertiarycourses.com.sg/wsq-kubernetes-and-cloud-native-associate-kcna-training.html).
