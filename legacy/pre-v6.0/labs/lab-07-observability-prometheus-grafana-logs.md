# Lab 07 - Observability, Prometheus, Grafana, Logs

## Objectives

- Explain logs, metrics, and traces.
- Inspect Pod logs and events.
- Understand Prometheus and Grafana roles.
- Explain cloud native observability.
- Identify cost and reliability signals.

## Scenario

Users report intermittent errors. You need to explain what data helps operators understand the system.

## Steps

### 1. Define Observability Signals

| Signal | Description | Example |
| --- | --- | --- |
| Logs | Text records of events | Application error log |
| Metrics | Numeric measurements over time | CPU usage |
| Traces | Request path across services | API call through microservices |

### 2. Inspect Kubernetes Events

```bash
kubectl get events --sort-by=.metadata.creationTimestamp
```

Record one event and what it means.

### 3. Inspect Pod Logs

```bash
kubectl get pods
kubectl logs POD_NAME
```

If multiple containers exist, note that `-c CONTAINER_NAME` selects a container.

### 4. Describe Observability Tools

Record:

```text
Prometheus: collects and stores metrics.
Grafana: visualizes metrics in dashboards.
Alertmanager: routes alerts.
OpenTelemetry: standardizes telemetry collection.
```

### 5. Choose Useful Signals

For a web app, choose availability, latency, error rate, saturation, Pod restarts, resource usage, and cost trend.

## Validation

You should have observability definitions, event notes, log notes, and a dashboard signal list.

## Cleanup

No cleanup is required unless you installed optional observability tools.

## Checkpoint Questions

1. What is the difference between logs and metrics?
2. What does Prometheus do?
3. What does Grafana do?
4. Why do microservices need tracing?

## Exam Focus

KCNA observability questions focus on concepts and tool roles, especially logs, metrics, traces, Prometheus, Grafana, and OpenTelemetry.
