# Learner Guide - Kubernetes and Cloud Native Associate (KCNA) Training

## Course Information

| Item | Details |
| --- | --- |
| Course Code | TGS-2023039343 |
| Course Title | Kubernetes and Cloud Native Associate (KCNA) Training |
| Registration | https://www.tertiarycourses.com.sg/wsq-kubernetes-and-cloud-native-associate-kcna-training.html |
| Study Guide Reference | https://devopscube.com/kcna-study-guide/ |

## Course Goal

This course helps learners understand Kubernetes and cloud native fundamentals for KCNA exam preparation. The labs are designed for beginners who need to recognize how Kubernetes works, what cloud native architecture means, how containers are orchestrated, how workloads are delivered, and how observability and security fit into the ecosystem.

## Prerequisites

- Basic command-line familiarity.
- Basic understanding of Linux processes and networking.
- Basic awareness of containers is helpful but not required.
- A laptop capable of running a local Kubernetes environment or access to an instructor-provided cluster.

## Learning Outcomes

By the end of the course, learners should be able to:

- Explain container and cloud native fundamentals.
- Describe Kubernetes control plane and worker node components.
- Use basic `kubectl` commands to inspect cluster resources.
- Create Pods, Deployments, ReplicaSets, and Services.
- Explain Kubernetes networking, DNS, ingress, and service discovery.
- Use ConfigMaps, Secrets, RBAC concepts, and Pod Security Standards.
- Explain persistent storage, StatefulSets, and autoscaling concepts.
- Describe observability using logs, metrics, traces, Prometheus, and Grafana.
- Explain CI/CD, GitOps, rolling updates, blue-green, and canary deployments.
- Recognize CNCF project categories such as networking, observability, service mesh, and serverless.

## Recommended Course Flow

### Day 1 - Kubernetes Fundamentals

1. Course briefing and KCNA exam overview.
2. Lab 01: Containers, Cloud Native Concepts, Kubernetes Overview.
3. Lab 02: Cluster Architecture, `kubectl`, Namespaces.
4. Lab 03: Pods, Deployments, ReplicaSets, Scheduling.
5. Lab 04: Services, Networking, DNS, Ingress Concepts.
6. Day 1 review: Kubernetes architecture and core resources.

### Day 2 - Cloud Native Operations and Delivery

1. Recap of Day 1.
2. Lab 05: ConfigMaps, Secrets, RBAC, Pod Security.
3. Lab 06: Storage, Stateful Workloads, Autoscaling.
4. Lab 07: Observability, Prometheus, Grafana, Logs.
5. Lab 08: CI/CD, GitOps, Application Delivery.
6. Lab 09: CNCF Landscape, Service Mesh, Serverless.
7. Lab 10: KCNA Capstone and Exam Readiness.

## Lab Environment Setup

### Step 1 - Choose a Cluster Option

| Option | Best For |
| --- | --- |
| Minikube | Simple local learning cluster |
| Kind | Lightweight local cluster using Docker containers |
| Docker Desktop Kubernetes | Easy setup for learners already using Docker Desktop |
| Instructor cluster | Classroom or cloud-hosted shared environment |

### Step 2 - Install kubectl

```bash
kubectl version --client
```

### Step 3 - Confirm Cluster Access

```bash
kubectl cluster-info
kubectl get nodes
kubectl get namespaces
```

If these fail, ask your instructor to verify your kubeconfig or local cluster.

### Step 4 - Create a Lab Namespace

```bash
kubectl create namespace kcna-lab
kubectl config set-context --current --namespace=kcna-lab
```

### Step 5 - Create a Notes File

Create `kcna-lab-notes.md` and record commands, errors, and exam takeaways after each lab.

## Cost and Safety Guidelines

- Prefer local clusters for practice.
- Avoid using production Kubernetes clusters.
- Do not deploy privileged Pods unless a lab explicitly discusses the risk.
- Do not store real passwords in sample Secrets.
- Delete test workloads after each lab.
- If using cloud Kubernetes, delete clusters and load balancers after class.

## Lab Completion Standard

For each lab, learners should complete:

1. Guided commands or diagrams.
2. Validation checks.
3. Cleanup steps.
4. Checkpoint questions.
5. One KCNA exam takeaway.

## Final Exam Readiness Checklist

Before attempting KCNA, confirm that you can:

- Explain Kubernetes architecture and control plane components.
- Explain Pods, Deployments, ReplicaSets, Jobs, CronJobs, Services, and Namespaces.
- Use basic `kubectl get`, `describe`, `logs`, `exec`, `apply`, and `delete` commands.
- Explain ConfigMaps, Secrets, RBAC, NetworkPolicy, Pod Security Standards, and service accounts.
- Explain container runtimes, CNI, CSI, CoreDNS, ingress, and service mesh at a high level.
- Explain microservices, serverless, autoscaling, elasticity, and CNCF project maturity.
- Explain logs, metrics, traces, Prometheus, Grafana, and OpenTelemetry concepts.
- Explain CI/CD, GitOps, rolling updates, canary, and blue-green deployment.
