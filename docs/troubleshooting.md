# Troubleshooting Log 

> **Source key**
> `[A]` = present in `Charles_Schwab_assignment.txt`
> `[C]` = surfaced only during the chat debugging session

All issues below are **[C]** — the attachment is a clean record of
commands and their (mostly successful) outputs, not an error log.

---

## Issue 1: Invalid project ID on creation — [C]

**Symptom:**
```
gcloud projects create balaji-GCP-observability-assignment-01 ...
ERROR: (gcloud.projects.create) argument PROJECT_ID: Bad value...
```
**Root cause:** Project IDs must be lowercase-only, 6–30 characters. The
attempted ID had uppercase letters and was 37 characters.
**Fix:** Renamed to `balaji-gcp-obs-poc-01` — **[A]** this is the ID used
throughout the attachment.
**Prevention:** Validate length/case before `create` — project IDs are
immutable once set.

## Issue 1b: `get-credentials` used wrong location type — [C]

**Symptom:** `ERROR: ... Not found: .../locations/us-central1/clusters/...`
plus a suggestion: `Did you mean [bn-observability-poc] in [us-central1-a]?`
**Root cause:** Cluster was created zonally (`--zone=us-central1-a`), but
`get-credentials` was run with `--region=us-central1`. Zonal and regional
are distinct location types in GKE.
**Fix:** Re-ran with `--zone=us-central1-a`, matching the creation command.
**Prevention:** Use the same location flag type (`--zone` vs `--region`)
consistently for a given cluster across all commands.

## Issue 2: Only 1 of 3 pod replicas scheduled on Cluster 1 — [C]

**Symptom:** `kubectl get pods` showed 1 `Running`, 2 `Pending`.
**Root cause:** Single `e2-small` node (2 vCPU/2GB), with capacity
reserved for system components, didn't have enough allocatable
CPU/memory for all 3 requested replicas.
**Fix:** Accepted 1 running replica on Cluster 1 as sufficient evidence of
a working endpoint (confirmed via `curl` — **[A]** the 200 OK response in
the attachment is from this single scheduled pod). Not resolved by
resizing Cluster 1; instead, Cluster 2 was later built on GKE Autopilot,
which scheduled all 3 replicas with no capacity issue — see Issue 5 and
`command-log.md` §3.
**Prevention:** Either size Standard node pools to match intended replica
count up front, or use Autopilot, which allocates capacity per-pod.

## Issue 3: `bq add-iam-policy-binding` blocked by allowlisting — [C]

**Symptom:**
```
BigQuery error in add-iam-policy-binding operation: This feature requires allowlisting.
```
**Root cause:** Dataset-level IAM binding via this `bq` CLI command is
gated behind a Google-side allowlist not enabled for this account. The
pre-existing `projectWriters` special-group entry on the dataset was
confirmed unrelated (covers project Editors generally, not this specific
service account).
**Fix:** Granted the same permission via BigQuery Console → Dataset →
Sharing → Permissions → Add Principal →
`service-694017227537@gcp-sa-logging.iam.gserviceaccount.com` → role:
BigQuery Data Editor → Save. Confirmed via `bq show --format=prettyjson`.

> Note: **[A]** the attachment shows a different intended fix — a
> `dataset.json` edit adding the same account as `WRITER` via
> `bq update --source=dataset.json`. That was offered as a fallback in
> chat but the Console path is what was actually confirmed working.

**Prevention:** When a `bq`/`gcloud` IAM command returns "requires
allowlisting," switch to the Console UI rather than retrying.

## Issue 4: BigQuery table name assumption was wrong — [C]

**Symptom:** Query against an assumed `stdout_20260831` /
`k8s_container_20260831` table returned "table not found."
**Root cause:** Cloud Logging BigQuery sinks (non-partitioned mode)
create one table per **log name** (`stdout_<date>`, `stderr_<date>`), not
a single combined table. `hello-app` writes its request logs to
**stderr**, so only a `stderr_20260831` table (plus an unrelated
`GCEGuestAgent_20260831` VM-infra table) was ever going to appear.
**Fix:** Queried `gke_logs.stderr_20260831` filtered to
`resource.labels.pod_name LIKE "web-app-a%"` — returned the expected
`Serving request: /` log lines.
**Prevention:** Run `bq ls <project>:<dataset>` to see actual table names
before writing queries against an assumed one.

## Issue 5: GCE_STOCKOUT — Cluster 2 creation failed twice on zone capacity — [C]

**Symptom:** Two separate `gcloud container clusters create` attempts for
`bn-observability-poc-east`, in `us-east1-b` then `us-east1-c`, both ran
~35–40 minutes before failing with the same error:
```
Google Compute Engine: Not all instances running in IGM after 35m...
Current errors: [GCE_STOCKOUT]: Instance '...' creation failed: The zone
'...us-east1-b' does not have enough resources available to fulfill the
request. Try a different zone, or try again later.
```

**Root cause:** Google Cloud temporarily lacked available capacity for
the requested machine type (`e2-small`) in both zones tried within
`us-east1`. This is a transient regional/zonal capacity issue on
Google's side, not a configuration or quota problem — confirmed via
`gcloud container operations describe`, which showed a clean, error-free
`RUNNING` status right up until the stockout message appeared at the
35-minute mark in each attempt.

**Diagnostic approach:** Rather than waiting indefinitely a third time,
checked `gcloud container operations describe <operation-id> --region=<zone>`
directly for the specific error rather than inferring from a stuck
`PROVISIONING` status alone — this is what surfaced the exact
`GCE_STOCKOUT` reason on both occasions.

**Fix:** Switched strategy rather than retrying the same pattern a third
time:
1. Deleted the failed cluster
2. Created Cluster 2 as **GKE Autopilot** (`gcloud container clusters
   create-auto`) in a **different region** (`us-west1`) — Autopilot
   selects zone/capacity automatically rather than pinning to one
   zone/machine-type combination, which sidesteps single-zone stockouts
3. Succeeded on the first attempt, no stockout

**Prevention:** For time-boxed exercises, prefer Autopilot over Standard
when zone-specific capacity risk isn't worth absorbing — Standard's
explicit zone/machine-type pinning trades resilience against exactly this
failure mode for more predictable node sizing. If Standard is required,
build in a zone-fallback plan (try 2–3 zones) rather than assuming the
first choice will succeed.

## Issue 6: Grafana BigQuery plugin not pre-installed — [C]

**Symptom:** After deploying Grafana via the community Helm chart,
"BigQuery" did not appear as an option under Connections → Data sources
→ Add data source.

**Root cause:** The Helm chart deploys stock Grafana with no
non-core plugins bundled. The BigQuery data source
(`grafana-bigquery-datasource`) is a separate plugin that must be
installed explicitly.

**Fix:**
```bash
kubectl exec -it $(kubectl get pod -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}') \
  -- grafana-cli plugins install grafana-bigquery-datasource
kubectl rollout restart deployment grafana
```
Plugin appeared after the pod restarted (~30 seconds).

**Prevention:** For a Helm-deployed Grafana that needs a non-core data
source, either install the plugin via `grafana-cli` post-deploy (as
above) or set `GF_INSTALL_PLUGINS=grafana-bigquery-datasource` as an
environment variable in the Helm values at install time, which installs
it automatically on first boot rather than requiring a manual exec + restart.

## Issue 7: BigQuery data source auth failed — Cloud Resource Manager API disabled — [C]

**Symptom:** After configuring the BigQuery data source with a valid
service account JWT key, "Save & Test" failed:
```
[auth] Error connecting to resource manager: googleapi: Error 403:
Cloud Resource Manager API has not been used in project ... before or
it is disabled.
```

**Root cause:** The Grafana BigQuery plugin validates project access via
the Cloud Resource Manager API in addition to the BigQuery API itself.
This API was not part of the original `gcloud services enable` batch run
during initial project setup (only `container`, `bigquery`, `logging`,
and `monitoring` were enabled).

**Fix:**
```bash
gcloud services enable cloudresourcemanager.googleapis.com
```
Waited ~1–2 minutes for propagation, then retried "Save & Test" in
Grafana — succeeded.

**Prevention:** When a GCP integration authenticates via a service
account, check whether the *client library or plugin itself* calls
additional APIs beyond the obvious one (here, Resource Manager alongside
BigQuery) — the error message named the exact API and provided a direct
enablement link, which made this a fast fix once identified.

## Issue 8: Fleet registration failed — Workload Identity not enabled on Standard cluster — [C]

**Symptom:**
```
gcloud container fleet memberships register cluster1-membership ...
ERROR: FAILED_PRECONDITION: Workload Identity is not enabled on your
GKE cluster "...bn-observability-poc". Please enable GKE Workload
Identity first...
```
Cluster 2 (Autopilot) registered on the first attempt with the exact
same command; Cluster 1 (Standard) did not.

**Root cause:** GKE Autopilot clusters have Workload Identity enabled by
default; GKE Standard clusters do not, and the Fleet registration
command's `--enable-workload-identity` flag configures the *membership*
side of the relationship, not the cluster side — the cluster itself
needs a separate, explicit update first.

**Fix:**
```bash
gcloud container clusters update bn-observability-poc \
  --zone=us-central1-a \
  --workload-pool=balaji-gcp-obs-poc-01.svc.id.goog
```
This is a control-plane update, took roughly 7 minutes
(`17:11:38` → `17:18:50`). Fleet registration retried successfully
immediately after.

**Prevention:** Before registering a Standard cluster to a Fleet, check
Workload Identity status directly rather than assuming the register
command will handle it:
```bash
gcloud container clusters describe <cluster> --zone=<zone> \
  --format="value(workloadIdentityConfig.workloadPool)"
```
Empty output means it needs to be enabled first — budget the ~10 minute
control-plane update time into the plan.

## Issue 9: Fleet ingress enable — membership path used zone instead of region — [C]

**Symptom:**
```
gcloud container fleet ingress enable \
  --config-membership=projects/.../locations/us-central1-a/memberships/cluster1-membership
ERROR: INVALID_ARGUMENT: Membership "...locations/us-central1-a/memberships/cluster1-membership" does not exist
```

**Root cause:** `gcloud container fleet memberships list` displays
`LOCATION: us-central1` (the region) for this membership, even though
the underlying cluster is zonal (`us-central1-a`). The membership
resource path itself is keyed by region, not the cluster's zone — using
the zone in the path looks plausible but resolves to a non-existent
resource.

**Fix:** Re-ran with the region in the path instead of the zone:
```bash
gcloud container fleet ingress enable \
  --config-membership=projects/balaji-gcp-obs-poc-01/locations/us-central1/memberships/cluster1-membership
```

**Prevention:** Always copy the exact `LOCATION` value shown by
`gcloud container fleet memberships list` for membership-path arguments,
rather than substituting the cluster's own zone/region from memory —
they aren't always the same string even when related.

## Issue 10: Failover test — target cluster had zero running pods when needed — [C]

**Symptom:** During a live failover test (Cluster 2 scaled to 0 to
simulate an outage), the global LB correctly returned `502 Bad Gateway`
— but the 502 persisted well past the expected health-check detection
window. Checking Cluster 1 (the intended failover target) directly
showed **zero running `web-app-a` pods** — both replicas `Pending`.

**Root cause (two layers):**
1. **Immediate cause:** Cluster 1's HPA still had `minReplicas: 2` from
   earlier configuration, which kept recreating a second pod attempt
   every time a manual scale-to-1 was tried, causing rapid pod churn
   rather than a stable single replica.
2. **Underlying cause, found after fixing (1):** even with HPA corrected
   and only 1 replica requested, the pod still would not schedule —
   `Insufficient cpu`, with node CPU allocation at 90%. Investigating
   further (`kubectl get pods -A -o wide`) showed several GKE-managed
   system pods present that were not there before this session —
   `gke-mcs-importer`, GKE Managed Prometheus components under
   `gmp-system` — added automatically as a side effect of registering
   the cluster to a Fleet and enabling Multi-cluster Ingress earlier the
   same session. This system overhead alone consumed enough of the
   single node's capacity to block the application pod.

**Fix:**
```bash
kubectl patch hpa web-app-a --patch '{"spec":{"minReplicas":1}}'
gcloud container clusters resize bn-observability-poc \
  --node-pool=default-pool --num-nodes=2 --zone=us-central1-a
```
Resizing to 2 nodes gave enough headroom for both the new MCI-related
system pods and the application pod. Once the pod reached `Running`, the
LB detected it within roughly a minute and traffic shifted cleanly —
confirmed via 10 consecutive requests all landing on Cluster 1
(`Via: 1.1 google` header confirmed LB routing, not a direct connection).

**Prevention:** Enabling Fleet membership and Multi-cluster Ingress adds
real, permanent system-pod overhead to every participating cluster —
this should be accounted for in node sizing *before* enabling these
features, not discovered when a failover event actually needs the spare
capacity. For small/free-tier clusters specifically, budget at least one
extra node's worth of headroom beyond application requirements once MCI
is in the picture.

## Issue 11: HPA fighting manual `kubectl scale` during troubleshooting — [C]

**Symptom:** While debugging Issue 10, `kubectl scale deployment
web-app-a --replicas=1` did not produce a stable single pod — instead,
`kubectl get pods --watch` showed a pod name repeatedly appearing at
`0s` age, i.e., being created and immediately deleted in a loop.

**Root cause:** The Deployment's HPA (`kubectl get hpa`) still had
`MINPODS: 2` configured from earlier (Day 1) testing. HPA continuously
reconciles toward its own min/max regardless of manual `kubectl scale`
commands, so the manual scale-to-1 and the HPA's enforced minimum-of-2
were fighting each other on every reconcile loop.

**Fix:**
```bash
kubectl patch hpa web-app-a --patch '{"spec":{"minReplicas":1}}'
```
Pod churn stopped immediately after.

**Prevention:** Before manually scaling a Deployment that has an HPA
attached, check the HPA's own min/max first (`kubectl get hpa`) — a
manual scale command that conflicts with the HPA's bounds will not hold
and can produce a confusing rapid-recreate pattern that looks like a
scheduling failure rather than a configuration conflict.

---

