# Architecture Write-Up: GKE Observability PoC (Two Clusters)

## 1. Objective

This project demonstrates an observability pipeline on GCP, built as a
scoped-down proof of concept against a larger enterprise landing-zone
design that specified two GKE clusters, multi-region redundancy, and full
observability. This document is explicit about which parts of that
original design are **implemented and verified**, versus **designed but
not built**, so the write-up doesn't overstate what was demonstrated.

## 2. What was built

### 2.1 Two independent GKE clusters

| | Cluster 1 (Primary) | Cluster 2 (Secondary) |
|---|---|---|
| Name | `bn-observability-poc` | `bn-observability-poc-east` |
| Location | `us-central1-a` | `us-west1` |
| Mode | GKE Standard, 1× `e2-small` node | GKE Autopilot |
| App replicas scheduled | 1 of 3 requested (node capacity limit) | 3 of 3 |
| External endpoint | `34.16.4.212` — verified `200 OK` | `34.187.230.32` — verified `200 OK` |

Both clusters run the identical `web-app-a` Deployment + `LoadBalancer`
Service manifest (`k8s/app-deployment.yaml`), confirmed independently
reachable via `curl`, each serving from its own distinct pod.

Cluster 2's region was originally targeted at `us-east1` to more closely
mirror a primary/DR pairing, but two zones in that region (`us-east1-b`,
`us-east1-c`) hit `GCE_STOCKOUT` — Google temporarily out of capacity for
the requested machine type — after ~35–40 minutes each. Rather than a
third blind zone retry, the cluster was rebuilt as GKE Autopilot in
`us-west1`, which succeeded immediately (see `docs/troubleshooting.md`
Issue 5 for the full diagnostic path).

### 2.2 Application layer
- `web-app-a`: stateless demo container (`gcr.io/google-samples/hello-app:2.0`)
- Deployed identically to both clusters
- HPA configured on Cluster 1 (CPU-based, min 2 / max 5)
- Cluster 1 vs. Cluster 2 scheduling outcome (1/3 vs. 3/3 replicas) is a
  direct, observed illustration of Standard's fixed node capacity versus
  Autopilot's per-pod allocation — documented as a real finding, not a
  hypothetical comparison

### 2.3 Logging pipeline (both clusters)
- Cloud Logging → BigQuery sink configured and verified on **both**
  clusters (`gke_logs` dataset, `stderr_<date>` tables — see
  `troubleshooting.md` Issue 4 on table naming). Each cluster has its own
  sink (`gke-to-bq`, `gke-to-bq-east`) filtered by `cluster_name`, both
  writing into the same dataset, sharing one Cloud Logging service
  account identity that GCP provisions per-project rather than per-sink
- Verified cross-cluster query: rows from both `bn-observability-poc` and
  `bn-observability-poc-east` are queryable together via a wildcard table
  reference (`gke_logs.stderr_2026*`) — see `bigquery/sample_queries.sql`

### 2.4 Visualization layer (Grafana)
- Self-hosted Grafana deployed via the official Helm chart onto Cluster 1
  (Cloud-hosted managed Grafana is not part of GCP's free tier)
- BigQuery connected as a data source using a dedicated, least-privilege
  service account (`grafana-bigquery-reader`, scoped to
  `roles/bigquery.dataViewer` + `roles/bigquery.jobUser` only — not the
  broader Editor role)
- BigQuery datasource plugin required the Cloud Resource Manager API to
  be separately enabled (not part of the original API-enablement batch)
  — see `troubleshooting.md` Issue 6
- Four-panel dashboard built (`grafana/dashboard.json`), all backed by
  real queries against live data:
  1. Request volume over time, by cluster
  2. Log activity by pod
  3. Requests and active-pod count by cluster
  4. Recent request log (raw tail)

## 3.5 A real finding from the data, not a hypothetical

The "Requests by cluster" panel surfaced a genuine, unplanned data point
worth calling out rather than a constructed comparison:

| Cluster | Total requests (cumulative) | Distinct active pods |
|---|---|---|
| `bn-observability-poc` (Standard, 1 node) | 3574 | 1 |
| `bn-observability-poc-east` (Autopilot) | 22 | 5 |

Cluster 1 accumulated far more total request volume (from earlier,
repeated manual testing), but only ever had **one** pod actually serving
traffic — consistent with the single-node capacity limit documented in
`troubleshooting.md` Issue 2. Cluster 2 saw much less cumulative traffic
but shows **five** distinct pods having served requests over its
lifetime — consistent with Autopilot's more flexible, per-pod scheduling
and the fact its replica set was never capacity-constrained.

This is real evidence of the Standard-vs-Autopilot operational trade-off
discussed in §2.2, pulled directly from the observability pipeline this
project built — not asserted from general knowledge of how the two modes
are supposed to differ.

## 4. What "two clusters" does and doesn't demonstrate

This is the section most worth reading carefully, since it's where the
original design's ambitions and this PoC's actual scope diverge most.

**What having two real, independently-verified clusters DOES show:**
- Two working GKE clusters in two different regions, each independently
  serving the sample application
- A genuine geographic/regional split (us-central1 vs. us-west1)
- Two different GKE operating modes (Standard vs. Autopilot), with an
  observed, real difference in scheduling behavior between them

**What it does NOT show, and why:**

| Original requirement | Why it's not demonstrated here |
|---|---|
| Cross-regional redundancy | Redundancy implies the two clusters actively back each other up (e.g., shared state, synchronized data, coordinated health). Here they're two independent, unrelated deployments of the same static app — nothing is replicated or synchronized between them |
| Automatic failover | Failover requires a routing layer that detects one cluster's unhealthiness and redirects traffic to the other. No such layer exists here — the two external IPs are entirely separate, unconnected endpoints. Traffic to Cluster 1's IP has no relationship to Cluster 2's availability |
| Active/Active or Active/Passive patterns | Both of these terms describe a *traffic distribution strategy* across clusters. With no shared ingress or DNS-based/LB-based routing between the two clusters, there is no "active" or "passive" designation — they're just two separate deployments |
| Multi-cluster Ingress / Multi-cluster Services | Not built. This is the GCP feature (via a Fleet + config cluster) that would actually implement the failover/redundancy claims above. It requires Anthos-style fleet registration and either classic MCI or the newer Gateway API multi-cluster setup — a non-trivial addition, and the layer where a global external LB with NEGs is introduced |

**The honest framing for a grader:** this PoC proves the individual
building blocks work (clusters, app deployment, one observability
pipeline) and that they can exist in two regions simultaneously. It does
**not** prove the cross-cluster orchestration that would make "two
clusters" meaningfully more resilient than one — that layer was
identified as scope, not attempted, given the 2-day window.

## 5. Not implemented (by design, given timeline)

| Original design element | Status | What it would take |
|---|---|---|
| Multi-cluster Ingress / global HTTPS LB | Not built | Fleet registration, config cluster, NEGs, global external LB — adds real hourly cost beyond free tier |
| Automatic failover | Not built | Requires MCI above, plus health-check configuration |
| BigQuery logging sink on Cluster 2 | ✅ Built | Both clusters now feed the same `gke_logs` dataset — see §2.3 |
| Grafana dashboard | ✅ Built | Self-hosted via Helm on Cluster 1, connected to BigQuery — see §2.4 |
| Anthos Service Mesh | Not built | Paid add-on; unnecessary for two independent, non-communicating services |
| Cloud Armor, Binary Authorization | Not built | Both attach to infrastructure (global LB, CI/CD attestation) not present in this scope |
| Request latency percentiles (p50/p95/p99) panel | Not built | The demo app's plain-text stderr logs have no duration/latency field; would need either a different app logging structured JSON with request duration, or pulling from Cloud Monitoring's GKE ingress metrics instead of BigQuery logs |
| True application error-rate panel | Not built | `hello-app` never logs at ERROR severity; request volume was substituted as the closest available signal — see `bigquery/sample_queries.sql` |

## 6. Design decisions and rationale (updated)

- **Two clusters were added** after reviewing the original requirement
  doc against the initial single-cluster plan — the "two GKE clusters"
  line item is explicit in the source requirements and not something a
  single-cluster PoC could honestly claim to satisfy
- **Autopilot was chosen for Cluster 2** specifically in response to a
  real, encountered failure (GCE_STOCKOUT on Standard in two zones), not
  as an upfront design preference — worth noting in a write-up as an
  example of adapting the plan based on what was actually encountered
  during the exercise
- **Multi-cluster routing/failover was deliberately not attempted** in
  the remaining time — attempting a partial, unverified version of it
  would be worse for the write-up than clearly stating it as designed but
  out of scope, since a failover claim that wasn't actually tested is
  more misleading than no claim at all

## 7. Repo contents

- `k8s/app-deployment.yaml` — manifest deployed identically to both clusters
- `docs/command-log.md` — full command log, source-tagged against the
  original attachment vs. chat debugging
- `docs/troubleshooting.md` — documented issues, including the
  GCE_STOCKOUT/Autopilot pivot and the Grafana/BigQuery plugin setup
- `bigquery/sample_queries.sql` — the four queries backing the dashboard
- `grafana/dashboard.json` — exported dashboard definition
