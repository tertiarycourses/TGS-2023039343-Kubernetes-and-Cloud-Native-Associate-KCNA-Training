# Lab 03 - Pods, Deployments, ReplicaSets, Scheduling

## Objectives

- Create a Pod.
- Create a Deployment.
- Scale replicas.
- Observe ReplicaSets.
- Understand basic scheduling behavior.

## Scenario

The team wants to run a small web application. You will start with a Pod, then use a Deployment to manage replicas.

## Steps

### 1. Create a Pod

```bash
kubectl run kcna-nginx --image=nginx:stable --port=80
kubectl get pods
kubectl describe pod kcna-nginx
```

### 2. View Logs

```bash
kubectl logs kcna-nginx
```

### 3. Delete the Pod

```bash
kubectl delete pod kcna-nginx
```

Explain why a standalone Pod is not ideal for resilient applications.

### 4. Create a Deployment

```bash
kubectl create deployment kcna-web --image=nginx:stable
kubectl get deployment
kubectl get replicaset
kubectl get pods
```

### 5. Scale the Deployment

```bash
kubectl scale deployment kcna-web --replicas=3
kubectl get pods -o wide
```

Record which nodes the Pods are scheduled on.

### 6. Test Self-Healing

```bash
kubectl delete pod POD_NAME
kubectl get pods
```

Observe that the Deployment creates a replacement Pod.

## Validation

You should see one Deployment, one ReplicaSet, and three running Pods.

## Cleanup

Keep the Deployment for Lab 04.

## Checkpoint Questions

1. What is the smallest deployable unit in Kubernetes?
2. What does a Deployment manage?
3. What does a ReplicaSet do?
4. What does the scheduler decide?

## Exam Focus

Know the relationship between Deployment, ReplicaSet, and Pod.
