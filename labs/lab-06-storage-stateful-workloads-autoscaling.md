# Lab 06 - Storage, Stateful Workloads, Autoscaling

## Objectives

- Explain ephemeral and persistent storage.
- Understand PersistentVolumes and PersistentVolumeClaims.
- Review StatefulSet concepts.
- Explain horizontal, vertical, and cluster autoscaling.

## Scenario

The team wants to run a database in Kubernetes. You must explain why stateful workloads need careful storage and scaling decisions.

## Steps

### 1. Compare Storage Types

| Storage Type | Description | Risk |
| --- | --- | --- |
| Ephemeral | Lives with the Pod | Lost when Pod is deleted |
| Persistent | Managed independently from Pod lifecycle | Needs storage class and backup plan |

### 2. Inspect Storage Classes

```bash
kubectl get storageclass
```

If no storage class exists, note that your local cluster may not provide dynamic provisioning.

### 3. Create a PVC

Create `pvc-demo.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: kcna-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

Apply:

```bash
kubectl apply -f pvc-demo.yaml
kubectl get pvc
```

### 4. Review StatefulSet and Autoscaling Concepts

Explain stable network identity, stable storage, ordered deployment, ordered scaling, and ordered termination. Compare HPA, VPA, and Cluster Autoscaler.

## Validation

You should have storage notes, PVC status, StatefulSet concept notes, and autoscaling comparison.

## Cleanup

```bash
kubectl delete pvc kcna-pvc
```

## Checkpoint Questions

1. Why can Pod storage be temporary?
2. What does a PVC request?
3. Why are StatefulSets different from Deployments?
4. What is the difference between HPA and Cluster Autoscaler?

## Exam Focus

KCNA expects high-level understanding of persistent storage, CSI, StatefulSets, and autoscaling.
