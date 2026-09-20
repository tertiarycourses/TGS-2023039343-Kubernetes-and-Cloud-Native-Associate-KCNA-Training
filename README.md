# Kubernetes and Cloud Native Associate (KCNA) Training

**WSQ Course Reference:** `TGS-2023039343`  ·  **Version:** v6.1  ·  **Duration:** 5 days / 40 hours (37 training + 3 assessment)

Hands-on lab repository for the *Kubernetes and Cloud Native Associate (KCNA) Training* course delivered by **Tertiary Infotech Academy Pte Ltd** (UEN 201200696W).

This course prepares you for the Linux Foundation / CNCF **Kubernetes and Cloud Native Associate (KCNA)** certification while meeting the registered Singapore WSQ competency standard **Solution Architecture (ICT-DES-4006-1.1)**.

---

## About this course

| | |
|---|---|
| **Course title** | Kubernetes and Cloud Native Associate (KCNA) Training |
| **TGS reference** | `TGS-2023039343` |
| **Duration** | 5 days, 40 hours (37 h training + 3 h assessment) |
| **Daily schedule** | 9:30 AM – 6:30 PM |
| **Competency standard** | Solution Architecture (ICT-DES-4006-1.1) |
| **Assessment** | Written Assessment (SAQ) 60 minutes + Practical Performance 120 minutes, open book |
| **Awarded on competency** | WSQ Statement of Attainment (SOA) |
| **Registration** | [https://www.tertiarycourses.com.sg/wsq-kubernetes-and-cloud-native-associate-kcna-training.html](https://www.tertiarycourses.com.sg/wsq-kubernetes-and-cloud-native-associate-kcna-training.html) |

Funding of up to 70% is available to eligible learners; eligibility and terms apply. See the registration page for current fees, funding and upcoming dates.

## Learning outcomes

By the end of this course you will be able to:

- **LO1** — Develop a Kubernetes architectural proof of concept. *(A1; K1)*
- **LO2** — Identify the technical and practical requirements in a Kubernetes setup. *(A3; K3)*
- **LO3** — Develop a solution architecture within Kubernetes. *(A2; K2, K4)*
- **LO4** — Prepare a technical blueprint for a Kubernetes-based solution for security and storage. *(A4; K6)*
- **LO5** — Demonstrate Kubernetes solution for a specific business problem. *(A5; K5)*
- **LO6** — Implement regular monitoring of the Kubernetes system and perform necessary troubleshooting. *(A6; K7)*

## KCNA certification alignment

The course is mapped to the current official CNCF KCNA exam blueprint:

| Domain | Weight | Covered in |
|---|---|---|
| Kubernetes Fundamentals | 44% | Days 1–2 |
| Container Orchestration | 28% | Days 2–3 |
| Cloud Native Application Delivery | 16% | Day 4 |
| Cloud Native Architecture | 12% | Days 1 and 5 |

*Source: CNCF Curriculum repository, KCNA_Curriculum.pdf (github.com/cncf/curriculum), revision effective 24 Nov 2025. Retrieved 10 Sep 2026.*

Exam format: 60 multiple-choice questions, 90 minutes, 75% to pass, certification valid for 2 years, no prerequisites. Practice papers: [https://exams.tertiaryinfotech.com/practice-exams/linuxfoundation/linuxfoundation-kcna](https://exams.tertiaryinfotech.com/practice-exams/linuxfoundation/linuxfoundation-kcna)

## Before you start

Use the browser-based Killercoda Kubernetes Playground for the standard lab path. A local cluster is the fallback for advanced labs that need extra components or a longer session:

- **[Killercoda Kubernetes Playground](https://killercoda.com/playgrounds/scenario/kubernetes)** (recommended) — disposable Kubernetes cluster and terminal in the browser.
- **[kind](https://kind.sigs.k8s.io/)** — local fallback that runs a cluster in Docker. Needs Docker Desktop, Rancher Desktop or Podman.
- **[minikube](https://minikube.sigs.k8s.io/)** — the alternative named in the course outline.
- **Docker Desktop** with the built-in Kubernetes option enabled.

```bash
# verify the Killercoda or local cluster before Lab 01
kubectl version --client
kubectl get nodes
```

Full platform-by-platform setup instructions for macOS, Windows and Linux are in the **Learner Guide**, which your trainer issues on the LMS at [https://lms-tms.tertiaryinfotech.com/](https://lms-tms.tertiaryinfotech.com/).

> **Safety.** Every lab creates its own namespace and cleans up only that namespace. Run the labs on a cluster you own. Do not run them against a shared or production cluster.

## The labs

25 self-contained labs. Each folder holds a full step-by-step `README.md`, runnable Kubernetes manifests, a realistic dataset, and a verification script.

```bash
git clone https://github.com/tertiarycourses/TGS-2023039343-Kubernetes-and-Cloud-Native-Associate-KCNA-Training.git
cd TGS-2023039343-Kubernetes-and-Cloud-Native-Associate-KCNA-Training/courseware/labs
```

### Day 1 — Cloud Native Foundations & Kubernetes Core Concepts

*Cloud native foundations, containers and the OCI/CRI stack, the Kubernetes API and cluster architecture, Pods and manifests.*

| Lab | Title | Namespace | Time | Maps to |
|---|---|---|---|---|
| **Lab 01** | [Cluster Reconnaissance with kubectl](courseware/labs/lab-01-kubectl-and-cluster-recon/README.md) | `kcna-lab01` | 45 min | LO1 · A1 · K1 |
| **Lab 02** | [Authoring Your First Pod Manifest](courseware/labs/lab-02-first-pod-manifest/README.md) | `kcna-lab02` | 45 min | LO1 · A1 · K1 |
| **Lab 03** | [Commands, Arguments and Environment](courseware/labs/lab-03-commands-args-env/README.md) | `kcna-lab03` | 40 min | LO1 · A1 · K1 |
| **Lab 04** | [Multi-Container Pod Patterns: Sidecar, Adapter, Ambassador](courseware/labs/lab-04-multi-container-patterns/README.md) | `kcna-lab04` | 50 min | LO1 · A1 · K1 |
| **Lab 05** | [Container Images, OCI and the Runtime Interface](courseware/labs/lab-05-container-images-oci/README.md) | `kcna-lab05` | 40 min | LO1 · A1 · K1 |

### Day 2 — Workloads, Scheduling & Container Orchestration

*Labels and selectors, ReplicaSets and Deployments, rollout and rollback, DaemonSets/Jobs/CronJobs, scheduling, resources and autoscaling.*

| Lab | Title | Namespace | Time | Maps to |
|---|---|---|---|---|
| **Lab 06** | [Labels, Selectors and ReplicaSets](courseware/labs/lab-06-labels-selectors-replicasets/README.md) | `kcna-lab06` | 45 min | LO2 · A3 · K3 |
| **Lab 07** | [Deployments, Rollout Strategy and Rollback](courseware/labs/lab-07-deployments-rollout-rollback/README.md) | `kcna-lab07` | 55 min | LO2 · A3 · K3 |
| **Lab 08** | [DaemonSets, Jobs and CronJobs](courseware/labs/lab-08-daemonsets-jobs-cronjobs/README.md) | `kcna-lab08` | 45 min | LO2 · A3 · K3 |
| **Lab 09** | [Scheduling: nodeSelector, Affinity, Taints and Tolerations](courseware/labs/lab-09-scheduling-affinity-taints/README.md) | `kcna-lab09` | 55 min | LO2 · A3 · K3 |
| **Lab 10** | [Resource Requests, Limits, QoS and Autoscaling](courseware/labs/lab-10-resources-requests-limits-autoscaling/README.md) | `kcna-lab10` | 50 min | LO2 · A3 · K3 |

### Day 3 — Services, Networking & Cluster Security

*Services, EndpointSlices and cluster DNS, Service types, Ingress routing, namespaces and RBAC, Secrets and ConfigMaps, NetworkPolicy.*

| Lab | Title | Namespace | Time | Maps to |
|---|---|---|---|---|
| **Lab 11** | [Services, Endpoints and Cluster DNS](courseware/labs/lab-11-services-endpoints/README.md) | `kcna-lab11` | 50 min | LO3 · A2 · K2 K4 |
| **Lab 12** | [Service Types: ClusterIP, NodePort and LoadBalancer](courseware/labs/lab-12-service-types-nodeport-lb/README.md) | `kcna-lab12` | 45 min | LO3 · A2 · K2 K4 |
| **Lab 13** | [Ingress Resources and HTTP Routing](courseware/labs/lab-13-ingress-routing/README.md) | `kcna-lab13` | 50 min | LO3 · A2 · K2 K4 |
| **Lab 14** | [Namespaces, ServiceAccounts and RBAC](courseware/labs/lab-14-namespaces-serviceaccounts-rbac/README.md) | `kcna-lab14` | 55 min | LO4 · A4 · K6 |
| **Lab 15** | [Secrets, ConfigMaps and Safe Injection](courseware/labs/lab-15-secrets-configmaps/README.md) | `kcna-lab15` | 50 min | LO4 · A4 · K6 |
| **Lab 16** | [NetworkPolicy and Default-Deny Isolation](courseware/labs/lab-16-networkpolicy-isolation/README.md) | `kcna-lab16` | 50 min | LO4 · A4 · K6 |

### Day 4 — Storage, Cluster Architecture & Application Delivery

*Volumes, PersistentVolumes and StorageClasses, StatefulSets, control plane anatomy and etcd, and application delivery with Helm, Kustomize and GitOps.*

| Lab | Title | Namespace | Time | Maps to |
|---|---|---|---|---|
| **Lab 17** | [Volumes: emptyDir, hostPath and the Container Filesystem](courseware/labs/lab-17-volumes-emptydir-hostpath/README.md) | `kcna-lab17` | 45 min | LO4 · A4 · K6 |
| **Lab 18** | [PersistentVolumes, Claims and StorageClasses](courseware/labs/lab-18-pv-pvc-storageclass/README.md) | `kcna-lab18` | 55 min | LO4 · A4 · K6 |
| **Lab 19** | [StatefulSets, Headless Services and Stable Identity](courseware/labs/lab-19-statefulset-headless/README.md) | `kcna-lab19` | 50 min | LO4 · A4 · K6 |
| **Lab 20** | [Control Plane Anatomy and etcd Backup/Restore](courseware/labs/lab-20-cluster-architecture-etcd/README.md) | `kcna-lab20` | 55 min | LO5 · A5 · K5 |
| **Lab 21** | [Packaging and Delivery: Helm, Kustomize and GitOps](courseware/labs/lab-21-helm-kustomize-gitops/README.md) | `kcna-lab21` | 55 min | LO5 · A5 · K5 |

### Day 5 — Observability, Troubleshooting & Assessment

*Probes and self-healing, Events, logs and metrics, Prometheus and the observability pipeline, troubleshooting triage, and exam readiness.*

| Lab | Title | Namespace | Time | Maps to |
|---|---|---|---|---|
| **Lab 22** | [Probes, Health and Self-Healing](courseware/labs/lab-22-probes-health-selfhealing/README.md) | `kcna-lab22` | 45 min | LO6 · A6 · K7 |
| **Lab 23** | [Events, Logs, Field Selectors and the Metrics Server](courseware/labs/lab-23-events-logs-metrics/README.md) | `kcna-lab23` | 50 min | LO6 · A6 · K7 |
| **Lab 24** | [Metrics, Prometheus Exposition and the Observability Pipeline](courseware/labs/lab-24-prometheus-observability/README.md) | `kcna-lab24` | 45 min | LO6 · A6 · K7 |
| **Lab 25** | [Troubleshooting Triage: Application, Node and Control Plane](courseware/labs/lab-25-troubleshooting-triage/README.md) | `kcna-lab25` | 55 min | LO6 · A6 · K7 |

## Lab folder structure

```
courseware/labs/<lab>/
├── README.md                    full step-by-step procedure
├── manifests/                   runnable Kubernetes YAML
├── data/                        the dataset the lab actually uses
└── verification/
    ├── checks.sh                run this to prove your work
    └── expected-output.md       what you should have seen
```

Every lab README follows the same shape: objective, prerequisites, scenario, the numbered procedure with expected output, verification, a deliberate failure to diagnose, a troubleshooting table, and cleanup.

## Verifying your work

```bash
cd courseware/labs/lab-01-kubectl-and-cluster-recon
bash verification/checks.sh
```

Each script prints a PASS/FAIL line per check and exits non-zero if anything failed. Some checks report **SKIP** where a capability is not present on a stock kind cluster — for example the metrics-server, an Ingress controller, or a CNI plugin that enforces NetworkPolicy. A SKIP is not a failure; the affected lab READMEs explain exactly why and give an optional, pinned setup path.

## Cleaning up

```bash
# each lab's own namespace, and nothing else
kubectl delete namespace kcna-lab01
```

Every lab ends with its own cleanup section. Labs that create a cluster-scoped object delete it by exact name.

## Course materials

The full courseware package is published in [`courseware/`](courseware/README.md), in both its rendered and editable forms:

| Material | Formats |
|---|---|
| Slide deck | [PPTX](courseware/Kubernetes%20and%20Cloud%20Native%20Associate%20%28KCNA%29%20Training-v6.1.pptx) · [PDF](courseware/Kubernetes%20and%20Cloud%20Native%20Associate%20%28KCNA%29%20Training-v6.1.pdf) |
| Learner Guide | [DOCX](courseware/LG-Kubernetes%20and%20Cloud%20Native%20Associate%20%28KCNA%29%20Training-v6.1.docx) · [PDF](courseware/LG-Kubernetes%20and%20Cloud%20Native%20Associate%20%28KCNA%29%20Training-v6.1.pdf) · [Markdown](courseware/LG-Kubernetes%20and%20Cloud%20Native%20Associate%20%28KCNA%29%20Training-v6.1.md) |
| Lesson Plan | [DOCX](courseware/LP-Kubernetes%20and%20Cloud%20Native%20Associate%20%28KCNA%29%20Training-v6.1.docx) · [PDF](courseware/LP-Kubernetes%20and%20Cloud%20Native%20Associate%20%28KCNA%29%20Training-v6.1.pdf) |
| Labs | [25 labs with manifests, data and verification](courseware/labs/README.md) |

Enrolled learners also receive these on the LMS at [https://lms-tms.tertiaryinfotech.com/](https://lms-tms.tertiaryinfotech.com/).

### What is not published here

Assessment papers and answer keys, trainer-only source reference material, build tooling and QA renders, superseded versions, and the course application pack are confidential and are deliberately excluded from this public repository.

## Support

- **Tertiary Infotech Academy Pte Ltd** · UEN 201200696W
- Email: [enquiry@tertiaryinfotech.com](mailto:enquiry@tertiaryinfotech.com)
- Phone: +65 6100 0613
- Web: [www.tertiarycourses.com.sg](https://www.tertiarycourses.com.sg)
- Register: [https://www.tertiarycourses.com.sg/wsq-kubernetes-and-cloud-native-associate-kcna-training.html](https://www.tertiarycourses.com.sg/wsq-kubernetes-and-cloud-native-associate-kcna-training.html)

## Licence and attribution

Course content © 2026 Tertiary Infotech Academy Pte Ltd. All rights reserved.

Kubernetes and the CNCF project marks are trademarks of The Linux Foundation and their respective owners. Project logos used in the courseware come from the CNCF artwork repository and are used nominatively for training purposes under the Linux Foundation Trademark Usage Guidelines; this does not imply sponsorship or endorsement by The Linux Foundation, the CNCF or any named project.

*Kubernetes and Cloud Native Associate (KCNA) Training · TGS-2023039343 · v6.1 · 10 September 2026*
