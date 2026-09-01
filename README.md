# GKE Observability PoC

Observability pipeline on GCP: two GKE clusters running a sample web
application, with logs flowing into BigQuery for analysis and a
self-hosted Grafana dashboard for visualization. Built as a
free-tier-scoped proof of concept against a larger enterprise
architecture design (see `docs/architecture.md`, which is explicit about
what is and isn't demonstrated relative to that original design —
particularly around cross-cluster redundancy and failover).

## Status

- [x] Project setup, two GKE clusters (Standard + Autopilot), application
      deployment to both — see `docs/command-log.md`
- [x] Cloud Logging → BigQuery pipeline on both clusters — see
      `bigquery/sample_queries.sql`
- [x] Grafana dashboard (4 panels, self-hosted, BigQuery-backed) — see
      `grafana/dashboard.json`
- [x] Architecture write-up with explicit scope boundaries — see
      `docs/architecture.md`

## Repo layout

```
k8s/            Kubernetes manifests
docs/
  architecture.md    Full write-up: what was built and why, vs. original design
  command-log.md     Command log with actual outputs, source-annotated
  troubleshooting.md Issues hit and how they were resolved
bigquery/
  sample_queries.sql Queries backing the Grafana dashboard panels
grafana/
  dashboard.json      Exported dashboard definition
```

## Environment

- GCP project: `balaji-gcp-obs-poc-01`
- Cluster 1: `bn-observability-poc` (GKE Standard, `us-central1-a`, 1×`e2-small`)
- Cluster 2: `bn-observability-poc-east` (GKE Autopilot, `us-west1`)
- Application: `gcr.io/google-samples/hello-app:2.0`
- Logging: Cloud Logging → BigQuery sink (`gke_logs` dataset), both clusters
- Visualization: self-hosted Grafana (Helm, on Cluster 1) with the BigQuery
  data source plugin
