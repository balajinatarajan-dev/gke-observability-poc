-- Sample BigQuery queries used against the Cloud Logging -> BigQuery
-- sink (`gke_logs` dataset). Queries 1-4 back four of the five panels in
-- grafana/dashboard.json (the fifth panel, request latency percentiles,
-- is sourced from Cloud Monitoring directly, not BigQuery -- see the
-- note at the bottom of this file).
--
-- Schema notes:
--   - The sample application (gcr.io/google-samples/hello-app:2.0) logs
--     plain-text request lines to stderr, not stdout. Tables are named
--     by log stream + date: stderr_<YYYYMMDD>. The wildcard suffix
--     (stderr_2026*) below queries across all dates captured so far.
--   - resource.labels.cluster_name distinguishes the two clusters:
--     bn-observability-poc (Standard, us-central1-a) and
--     bn-observability-poc-east (Autopilot, us-west1).
--   - No structured JSON payload / duration field exists in these
--     application logs, so a latency query directly against this
--     BigQuery data was not possible -- see the note at the bottom of
--     this file for how latency percentiles were obtained instead.

-- 1. Request volume over time, by cluster
-- (stands in for "application error rates over time" -- see
-- docs/architecture.md for why a true error-rate query isn't possible
-- with this demo app, which never logs at ERROR severity)
SELECT
  TIMESTAMP_TRUNC(timestamp, MINUTE) AS time,
  resource.labels.cluster_name AS cluster,
  COUNT(*) AS request_count
FROM `balaji-gcp-obs-poc-01.gke_logs.stderr_2026*`
WHERE resource.labels.pod_name LIKE "web-app-a%"
GROUP BY time, cluster
ORDER BY time;


-- 2. Log activity by pod
-- (stands in for "pod restart counts by namespace" -- this demo
-- app/namespace setup doesn't produce restart events under normal
-- operation, so log volume per pod is used as the closest available
-- per-pod activity signal)
SELECT
  resource.labels.pod_name AS pod,
  resource.labels.cluster_name AS cluster,
  COUNT(*) AS log_lines
FROM `balaji-gcp-obs-poc-01.gke_logs.stderr_2026*`
WHERE resource.labels.pod_name LIKE "web-app-a%"
GROUP BY pod, cluster
ORDER BY log_lines DESC;


-- 3. Requests and active pod count by cluster
-- (real cross-cluster comparison, meaningful given two independently
-- provisioned clusters -- e.g. shows Cluster 1's single-node capacity
-- limit vs. Cluster 2's Autopilot scheduling flexibility)
SELECT
  resource.labels.cluster_name AS cluster,
  COUNT(*) AS total_requests,
  COUNT(DISTINCT resource.labels.pod_name) AS active_pods
FROM `balaji-gcp-obs-poc-01.gke_logs.stderr_2026*`
WHERE resource.labels.pod_name LIKE "web-app-a%"
GROUP BY cluster;


-- 4. Recent request log (raw tail, for spot-checking / sanity check)
SELECT
  timestamp,
  resource.labels.cluster_name AS cluster,
  resource.labels.pod_name AS pod,
  textPayload
FROM `balaji-gcp-obs-poc-01.gke_logs.stderr_2026*`
WHERE resource.labels.pod_name LIKE "web-app-a%"
ORDER BY timestamp DESC
LIMIT 20;


-- 5. Request Latency Percentiles (p50/p95/p99) -- NOT a BigQuery query.
--
-- This panel is sourced directly from Cloud Monitoring (Grafana's
-- built-in Google Cloud Monitoring data source), not from the BigQuery
-- log data above. It became available specifically because building
-- Multi-cluster Ingress (see docs/architecture.md S2.5) provisioned a
-- real Global External HTTPS Load Balancer, which GCP automatically
-- instruments with the metric loadbalancing.googleapis.com/
-- application_lb/backend_latencies -- a distribution-type metric GCP
-- computes percentiles from natively, with no application code changes
-- and no BigQuery export required.
--
-- The Grafana panel runs three queries against this one metric, each
-- with a different percentile aligner:
--   Query A: perSeriesAligner = ALIGN_PERCENTILE_50  (aliased "p50")
--   Query B: perSeriesAligner = ALIGN_PERCENTILE_95  (aliased "p95")
--   Query C: perSeriesAligner = ALIGN_PERCENTILE_99  (aliased "p99")
--
-- Observed values at time of writing: p50 = 68.0ms, p95 = 78.2ms,
-- p99 = 79.1ms -- a sensible progression (p99 >= p95 >= p50), pulled
-- from GCP's own load balancer instrumentation, not synthesized.
--
-- This metric was not available before the Multi-cluster Ingress work:
-- the original per-cluster `LoadBalancer` Services (k8s/app-deployment.
-- yaml) are basic TCP/network load balancers with no equivalent
-- backend-latency metric. The global HTTPS LB from MCI is what exposes
-- this data.
