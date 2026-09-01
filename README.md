# GKE Observability PoC

Observability pipeline on GCP: two GKE clusters running a sample web
application, with logs flowing into BigQuery for analysis and Grafana for
visualization. Built as a free-tier-scoped proof of concept against a
larger enterprise architecture design (see `docs/architecture.md`).

## Status

- [x] Project setup, two GKE clusters, application deployment, Cloud
      Logging → BigQuery pipeline (see `docs/command-log.md`)
- [ ] BigQuery sample queries, Grafana dashboard, final write-up

## Repo layout

```
k8s/            Kubernetes manifests
docs/
  architecture.md    Full write-up: what was built and why, vs. original design
  command-log.md     Command log with actual outputs, source-annotated
  troubleshooting.md Issues hit and how they were resolved
bigquery/       Sample queries (pending)
grafana/        Dashboard export (pending)
```

## Environment

- GCP project: `balaji-gcp-obs-poc-01`
- Cluster 1: `bn-observability-poc` (GKE Standard, `us-central1-a`, 1×`e2-small`)
- Cluster 2: `bn-observability-poc-east` (GKE Autopilot, `us-west1`)
- Application: `gcr.io/google-samples/hello-app:2.0`
- Logging: Cloud Logging → BigQuery sink (`gke_logs` dataset), Cluster 1 only
