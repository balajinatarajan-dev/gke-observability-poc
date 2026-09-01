-- Sample BigQuery queries used against the Cloud Logging -> BigQuery
-- sink (`gke_logs` dataset). All four queries below back the four
-- panels in grafana/dashboard.json.
--
-- Schema notes:
--   - The sample application (gcr.io/google-samples/hello-app:2.0) logs
--     plain-text request lines to stderr, not stdout. Tables are named
--     by log stream + date: stderr_<YYYYMMDD>. The wildcard suffix
--     (stderr_2026*) below queries across all dates captured so far.
--   - resource.labels.cluster_name distinguishes the two clusters:
--     bn-observability-poc (Standard, us-central1-a) and
--     bn-observability-poc-east (Autopilot, us-west1).
--   - No structured JSON payload / latency field exists in these logs,
--     so a true p50/p95/p99 latency query is not possible against this
--     data as-is (see docs/architecture.md for the documented gap and
--     what a production setup would add).

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
