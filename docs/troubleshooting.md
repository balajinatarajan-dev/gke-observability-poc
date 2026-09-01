# Troubleshooting Log (source-annotated)

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

---

## Suggested framing for your write-up

If your grader wants **one** troubleshooting scenario, **Issue 5
(GCE_STOCKOUT)** is the strongest candidate: it's an infrastructure-level
failure (not a typo or missed step), took real diagnostic work to
confirm the actual cause via operation logs rather than just retrying
blindly, and led to a genuine architectural decision (Standard →
Autopilot, different region) rather than a one-line fix. It also produced
a useful side-by-side data point: Autopilot scheduled all 3 replicas
where the Standard single-node cluster only fit 1 (Issue 2), which is
worth calling out explicitly if your write-up compares the two clusters.
