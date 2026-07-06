# Lab 02 - Cluster Architecture, kubectl, Namespaces

## Objectives

- Identify control plane and worker node components.
- Use basic `kubectl` inspection commands.
- Work with namespaces.
- Understand kubeconfig context.

## Scenario

You have been given access to a training Kubernetes cluster. Before deploying anything, you must inspect the cluster and understand its components.

## Steps

### 1. Confirm Cluster Access

```bash
kubectl cluster-info
kubectl get nodes
kubectl get namespaces
```

### 2. Identify Architecture Components

Define `kube-apiserver`, `etcd`, `kube-scheduler`, `kube-controller-manager`, `kubelet`, `kube-proxy`, container runtime, and CoreDNS.

### 3. Inspect Cluster Resources

```bash
kubectl get pods -A
kubectl get services -A
kubectl get deployments -A
```

Record what `-A` means.

### 4. Create a Namespace

```bash
kubectl create namespace kcna-lab
kubectl get namespace kcna-lab
kubectl config set-context --current --namespace=kcna-lab
```

### 5. Practice kubectl Help

```bash
kubectl explain pod
kubectl explain deployment
kubectl explain service
```

Write one useful field you discovered for each object.

## Validation

```bash
kubectl config view --minify
kubectl get all
```

Confirm your current namespace is `kcna-lab`.

## Cleanup

Keep the namespace for later labs.

## Checkpoint Questions

1. What does the API server do?
2. Why is etcd important?
3. What is the purpose of a namespace?
4. What is kubeconfig?

## Exam Focus

KCNA expects you to recognize cluster components and basic `kubectl` usage.
