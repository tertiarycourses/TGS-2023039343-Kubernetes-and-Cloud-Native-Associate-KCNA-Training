# Lab 01 - Containers, Cloud Native Concepts, Kubernetes Overview

## Objectives

- Explain containers and container images.
- Describe cloud native architecture.
- Compare monoliths and microservices.
- Explain why Kubernetes is used.
- Identify KCNA exam domains.

## Scenario

A development team wants to modernize a monolithic application. Management keeps hearing terms like containers, Kubernetes, microservices, and cloud native. You must explain the concepts clearly.

## Steps

### 1. Define Core Terms

Create a glossary entry for:

```text
Container image
Container
Container registry
Microservice
Kubernetes
Cloud native
Orchestration
```

### 2. Compare Application Styles

| Style | Benefits | Challenges |
| --- | --- | --- |
| Monolith | Simple deployment, fewer moving parts | Harder to scale parts independently |
| Microservices | Independent scaling and deployment | More network and operational complexity |

### 3. Explain Kubernetes Value

Write how Kubernetes helps with scheduling, restarting failed containers, scaling replicas, service discovery, rolling updates, and configuration management.

### 4. Draw a Simple Architecture

Use diagrams.net or a whiteboard:

```text
User -> Service -> Pods -> Containers
Control plane -> Worker nodes
```

### 5. Map KCNA Domains

Record Kubernetes fundamentals, container orchestration, cloud native architecture, observability, and application delivery.

## Validation

You should have a glossary, comparison table, architecture sketch, and KCNA domain list.

## Checkpoint Questions

1. What is the difference between an image and a container?
2. Why do microservices need stronger observability?
3. What does orchestration mean?
4. Why is KCNA broader than only Kubernetes commands?

## Exam Focus

KCNA tests broad conceptual understanding. Know Kubernetes basics, but also understand the wider cloud native ecosystem.
