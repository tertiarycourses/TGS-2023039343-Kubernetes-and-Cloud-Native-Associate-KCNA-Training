# Lab 04 - Services, Networking, DNS, Ingress Concepts

## Objectives

- Expose Pods using a Service.
- Understand ClusterIP, NodePort, and LoadBalancer.
- Explain service discovery and CoreDNS.
- Review ingress concepts.
- Understand basic network policy purpose.

## Scenario

The `kcna-web` Deployment is running, but users need a stable way to reach it. Pods can be replaced, so you need a Service.

## Steps

### 1. Confirm the Deployment

```bash
kubectl get deployment kcna-web
kubectl get pods -o wide
```

### 2. Create a ClusterIP Service

```bash
kubectl expose deployment kcna-web --port=80 --target-port=80 --name=kcna-web-svc
kubectl get service kcna-web-svc
kubectl describe service kcna-web-svc
```

### 3. Test Service DNS from a Temporary Pod

```bash
kubectl run curl-test --image=curlimages/curl:latest -it --rm --restart=Never -- sh
```

Inside the container:

```bash
curl http://kcna-web-svc
exit
```

### 4. Compare Service Types

| Service Type | Purpose |
| --- | --- |
| ClusterIP | Internal cluster access |
| NodePort | Expose on node IP and port |
| LoadBalancer | Cloud load balancer integration |
| ExternalName | DNS alias to external service |

### 5. Review Ingress and NetworkPolicy

Explain ingress, ingress controller, host-based routing, path-based routing, TLS termination, and why NetworkPolicy restricts Pod-to-Pod communication.

## Validation

```bash
kubectl get service
kubectl get endpoints kcna-web-svc
```

Confirm endpoints match running Pods.

## Cleanup

Keep the Deployment and Service for later review.

## Checkpoint Questions

1. Why do Pods need Services?
2. What does CoreDNS provide?
3. When would a LoadBalancer Service be used?
4. What is the purpose of Ingress?

## Exam Focus

KCNA expects service discovery and networking concepts more than advanced troubleshooting.
