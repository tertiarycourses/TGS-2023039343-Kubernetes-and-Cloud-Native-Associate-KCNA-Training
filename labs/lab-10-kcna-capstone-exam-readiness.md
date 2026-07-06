# Lab 10 - KCNA Capstone and Exam Readiness

## Objectives

- Review all KCNA domains.
- Design a simple cloud native application architecture.
- Explain Kubernetes objects and ecosystem tools.
- Build a personal exam study plan.
- Clean up lab resources.

## Scenario

You must present a beginner-friendly cloud native design for a small web application. The design should include Kubernetes workloads, networking, configuration, security, observability, and delivery.

## Steps

### 1. Draw the Architecture

Include container image, registry, Deployment, ReplicaSet, Pods, Service, Ingress, ConfigMap, Secret, persistent storage if needed, monitoring, and CI/CD or GitOps workflow.

### 2. Map Objects to Purpose

| Object or Concept | Purpose |
| --- | --- |
| Pod | Runs one or more containers |
| Deployment | Manages rollout and desired replicas |
| Service | Provides stable access to Pods |
| ConfigMap | Stores non-sensitive configuration |
| Secret | Stores sensitive configuration |
| Namespace | Organizes resources |

### 3. Review KCNA Domains

Rate confidence from 1 to 5 for Kubernetes fundamentals, container orchestration, cloud native architecture, cloud native observability, and cloud native application delivery.

### 4. Build an Exam Mistakes Log

For each missed question, record:

```text
Topic:
Wrong assumption:
Correct concept:
Command or definition to review:
```

### 5. Clean Up the Lab

```bash
kubectl delete all --all -n kcna-lab
kubectl delete configmap --all -n kcna-lab
kubectl delete secret --all -n kcna-lab
kubectl delete pvc --all -n kcna-lab
kubectl get all -n kcna-lab
```

If you created the namespace only for this class:

```bash
kubectl delete namespace kcna-lab
```

### 6. Create a 7-Day Study Plan

1. Day 1: Kubernetes architecture and objects.
2. Day 2: Pods, Deployments, Services, and scheduling.
3. Day 3: Security, RBAC, ConfigMaps, Secrets, NetworkPolicy.
4. Day 4: Storage, autoscaling, cloud native architecture.
5. Day 5: Observability tools and telemetry.
6. Day 6: CI/CD, GitOps, delivery strategies.
7. Day 7: Practice questions and mistakes log review.

## Validation

You should have an architecture diagram, object-purpose table, confidence matrix, study plan, and clean lab namespace.

## Checkpoint Questions

1. Which KCNA domain is your weakest?
2. Which Kubernetes object is most confusing?
3. How do Services and Pods relate?
4. What is one cloud native tool category you need to review?

## Exam Focus

KCNA rewards concept clarity. Know what each component does, why cloud native patterns exist, and how common ecosystem tools fit together.
