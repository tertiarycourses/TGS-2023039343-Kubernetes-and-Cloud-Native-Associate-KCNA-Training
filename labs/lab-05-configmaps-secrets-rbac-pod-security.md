# Lab 05 - ConfigMaps, Secrets, RBAC, Pod Security

## Objectives

- Create ConfigMaps and Secrets.
- Mount configuration into workloads.
- Understand RBAC concepts.
- Explain service accounts.
- Review Pod Security Standards.

## Scenario

The web app needs environment-specific configuration. The team also needs to understand how access control and Pod security work.

## Steps

### 1. Create a ConfigMap

```bash
kubectl create configmap app-config --from-literal=APP_MODE=training
kubectl get configmap app-config -o yaml
```

### 2. Create a Sample Secret

Use fake training data only:

```bash
kubectl create secret generic app-secret --from-literal=API_KEY=training-only
kubectl get secret app-secret
```

### 3. Add Config to a Pod

Create `config-demo.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: config-demo
spec:
  containers:
    - name: demo
      image: busybox:stable
      command: ["sh", "-c", "env && sleep 3600"]
      envFrom:
        - configMapRef:
            name: app-config
        - secretRef:
            name: app-secret
```

Apply it:

```bash
kubectl apply -f config-demo.yaml
kubectl logs config-demo
```

### 4. Review RBAC and Pod Security

Define Role, ClusterRole, RoleBinding, ClusterRoleBinding, and ServiceAccount. Then explain why Pods should run as non-root, avoid privileged mode, drop unnecessary Linux capabilities, and use read-only filesystems when possible.

## Validation

```bash
kubectl get configmap,secret,pod
kubectl describe pod config-demo
```

## Cleanup

```bash
kubectl delete pod config-demo
kubectl delete configmap app-config
kubectl delete secret app-secret
```

## Checkpoint Questions

1. What is the difference between a ConfigMap and a Secret?
2. Why are Kubernetes Secrets not a complete secrets management solution by themselves?
3. What does RBAC control?
4. Why should Pods avoid privileged mode?

## Exam Focus

KCNA security topics include RBAC, service accounts, Secrets, NetworkPolicy, and Pod Security Standards.
