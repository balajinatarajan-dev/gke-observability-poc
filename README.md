# GKE Observability PoC

Two GKE clusters running a sample web application behind a Global
External HTTPS Load Balancer with Multi-cluster Ingress, automatic
failover verified live, and an observability pipeline (Cloud Logging →
BigQuery → self-hosted Grafana). Built as a free-tier-scoped proof of
concept against a larger enterprise architecture design (see
`docs/architecture.md`, which is explicit about what is and isn't
demonstrated relative to that original design).

## Status

- [x] Project setup, two GKE clusters (Standard + Autopilot), application
      deployment to both — see `docs/command-log.md`
- [x] Cloud Logging → BigQuery pipeline on both clusters — see
      `bigquery/sample_queries.sql`
- [x] Grafana dashboard (5 panels — 4 BigQuery-backed + live latency
      percentiles from Cloud Monitoring, self-hosted) — see
      `grafana/dashboard.json`
- [x] Multi-cluster Ingress + automatic failover, verified with a live
      test (cluster taken down, traffic confirmed shifting to the
      other cluster) — see `docs/architecture.md` §2.5
- [x] Architecture write-up with explicit scope boundaries — see
      `docs/architecture.md`

## Repo layout

```
k8s/
  app-deployment.yaml  Application Deployment + per-cluster LoadBalancer Service
  mcs-service.yaml     ClusterIP backend Service (applied on both clusters)
  mcs.yaml             MultiClusterService (applied on config cluster)
  mci.yaml             MultiClusterIngress (applied on config cluster)
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
- Cluster 1: `bn-observability-poc` (GKE Standard, `us-central1-a`, 2×`e2-small`)
- Cluster 2: `bn-observability-poc-east` (GKE Autopilot, `us-west1`)
- Application: `gcr.io/google-samples/hello-app:2.0`
- Logging: Cloud Logging → BigQuery sink (`gke_logs` dataset), both clusters
- Visualization: self-hosted Grafana (Helm, on Cluster 1) with the BigQuery
  data source plugin
- Multi-cluster: Fleet with both clusters registered, Multi-cluster
  Ingress enabled, global VIP behind a Global External HTTPS Load
  Balancer
