# Lab 08 - CI/CD, GitOps, Application Delivery

## Objectives

- Explain CI/CD concepts.
- Compare continuous delivery and continuous deployment.
- Explain GitOps.
- Review rolling, canary, and blue-green deployment strategies.
- Perform a simple rolling update.

## Scenario

The team wants to release new versions of the web application safely and repeatedly. You must explain modern application delivery patterns.

## Steps

### 1. Define CI/CD Terms

Define Continuous Integration, Continuous Delivery, Continuous Deployment, Pipeline, Artifact, and GitOps.

### 2. Perform a Rolling Update

```bash
kubectl get deployment kcna-web -o wide
kubectl set image deployment/kcna-web nginx=nginx:latest
kubectl rollout status deployment/kcna-web
kubectl rollout history deployment/kcna-web
```

### 3. Roll Back

```bash
kubectl rollout undo deployment/kcna-web
kubectl rollout status deployment/kcna-web
```

### 4. Compare Deployment Strategies

| Strategy | Description |
| --- | --- |
| Rolling update | Gradually replaces old Pods |
| Blue-green | Switches traffic between two environments |
| Canary | Sends small traffic percentage to new version first |

### 5. Explain GitOps

Document that Git stores desired state, a controller reconciles cluster state with Git, changes are reviewed through pull requests, and drift can be detected and corrected.

### 6. Design a Simple Pipeline

```text
Commit code
Run tests
Build image
Scan image
Push image
Update manifest
Deploy or sync
Monitor rollout
```

## Validation

You should have rollout history, rollback confirmation, deployment strategy table, and pipeline design.

## Cleanup

Keep the `kcna-web` Deployment for the capstone or delete it after review.

## Checkpoint Questions

1. What is the difference between continuous delivery and continuous deployment?
2. Why is GitOps useful?
3. What is a canary deployment?
4. Why should rollbacks be planned?

## Exam Focus

KCNA application delivery topics include CI/CD, GitOps, rolling updates, canary, and blue-green deployments.
