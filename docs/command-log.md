# Command Log (source-annotated)

Project: `balaji-gcp-obs-poc-01`

> **Source key**
> `[A]` = copied from `Charles_Schwab_assignment.txt` (your own command/output log)
> `[C]` = from the chat debugging session (errors hit and resolved interactively, not in the attachment)

---

## 1. Project setup

```bash
gcloud projects create balaji-gcp-obs-poc-01 --name="bn-observability-poc"   # [A]
gcloud config set project balaji-gcp-obs-poc-01                              # [A]
```

Linked billing: **[A]**
```bash
gcloud billing accounts list
# 01D229-D133B4-C0289A
gcloud billing projects link balaji-gcp-obs-poc-01 --billing-account=01D229-D133B4-C0289A
```

Enabled required APIs: **[A]**
```bash
gcloud services enable container.googleapis.com \
  bigquery.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com
```

Checkpoint: **[A]**
```bash
gcloud config get-value project
# balaji-gcp-obs-poc-01
```

> **[C]** Not in the attachment: an earlier attempt used an invalid project
> ID (`balaji-GCP-observability-assignment-01` — uppercase, 37 characters)
> and failed. See `troubleshooting.md` Issue 1.

---

## 2. Cluster 1 — Primary (us-central1-a, GKE Standard)

```bash
gcloud container clusters create bn-observability-poc \
  --zone=us-central1-a \
  --num-nodes=1 \
  --machine-type=e2-small
```
**[A]** — `STATUS: RUNNING`, `MASTER_IP: 136.116.226.165`, node
`gke-bn-observability-poc-default-pool-e3ba292b-b1wp`.

```bash
gcloud container clusters get-credentials bn-observability-poc --zone=us-central1-a   # [A]
kubectl get nodes                                                                      # [A]
```

> **[C]** An earlier `get-credentials` attempt used `--region=us-central1`
> instead of `--zone=us-central1-a` and 404'd, since the cluster is zonal.
> See `troubleshooting.md` Issue 1b.

### App deployment — Cluster 1

Manifest: [`k8s/app-deployment.yaml`](../k8s/app-deployment.yaml) — 3-replica
Deployment + `LoadBalancer` Service. **[A]**

```bash
kubectl apply -f app-deployment.yaml
curl -v http://34.16.4.212
```
**[A]** — `200 OK`, `Hello, world!`, `Hostname: web-app-a-599966876-7zmdq`.

```bash
kubectl autoscale deployment web-app-a --cpu-percent=60 --min=2 --max=5   # [A]
```

> **[C]** With only 1 node (`e2-small`), only 1 of 3 replicas scheduled (2
> stayed `Pending` — insufficient allocatable capacity on the single
> node). Accepted as sufficient rather than resizing. See
> `troubleshooting.md` Issue 2. This contrasts directly with Cluster 2
> below, where Autopilot scheduled all 3 replicas with no capacity issue.

### Logging pipeline — Cluster 1

```bash
bq mk --dataset --location=US balaji-gcp-obs-poc-01:gke_logs   # [A]
gcloud logging sinks create gke-to-bq \
  bigquery.googleapis.com/projects/balaji-gcp-obs-poc-01/datasets/gke_logs \
  --log-filter='resource.type="k8s_container" AND resource.labels.cluster_name="bn-observability-poc"'
```
**[A]** — sink service account:
`service-694017227537@gcp-sa-logging.iam.gserviceaccount.com`

> **[C]** `bq add-iam-policy-binding` failed twice with an allowlisting
> error; permission was granted via the BigQuery Console instead. See
> `troubleshooting.md` Issue 3.

```bash
EXTERNAL_IP=$(kubectl get svc web-app-a-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
for i in $(seq 1 50); do curl -s http://$EXTERNAL_IP > /dev/null; done
```
**[A]**

> **[C]** Log table naming turned out to be `stderr_<date>` /
> `stdout_<date>` (per log stream), not `k8s_container_<date>` as
> originally assumed — `hello-app` logs to stderr specifically. See
> `troubleshooting.md` Issue 4. Confirmed via:
```bash
bq query --use_legacy_sql=false \
'SELECT timestamp, resource.labels.pod_name, textPayload
FROM `balaji-gcp-obs-poc-01.gke_logs.stderr_20260831`
WHERE resource.labels.pod_name LIKE "web-app-a%"
ORDER BY timestamp DESC LIMIT 10'
```
Rows returned, e.g. `web-app-a-599966876-7zmdq | Serving request: /`.

---

## 3. Cluster 2 — Secondary/DR (originally attempted us-east1, landed on us-west1, GKE Autopilot)

**[C]** — entirely from chat; not in the original attachment, added after
the assignment's "two GKE clusters" requirement was reviewed against the
initial single-cluster plan.

### First two attempts failed on capacity, not configuration

```bash
gcloud container clusters create bn-observability-poc-east \
  --zone=us-east1-b --num-nodes=1 --machine-type=e2-small
```
Failed after ~40 min:
```
[GCE_STOCKOUT]: Instance '...' creation failed: The zone
'projects/balaji-gcp-obs-poc-01/zones/us-east1-b' does not have enough
resources available to fulfill the request.
```

Retried in `us-east1-c` — same `GCE_STOCKOUT` error, also after ~40 min.
Two zones in the same region both out of `e2-small` capacity was treated
as a signal to change approach rather than try a third zone blind. See
`troubleshooting.md` Issue 5.

### Successful creation — switched to Autopilot, different region

```bash
gcloud container clusters delete bn-observability-poc-east --zone=us-east1-c --quiet
gcloud container clusters create-auto bn-observability-poc-east --region=us-west1
```
Result: `STATUS: RUNNING`, `LOCATION: us-west1`, `MASTER_IP: 136.118.127.82`.
No stockout — Autopilot's automatic placement across zones avoided the
single-zone capacity issue that blocked both prior attempts.

### App deployment — Cluster 2

```bash
gcloud container clusters get-credentials bn-observability-poc-east --region=us-west1
kubectl config current-context   # confirmed pointed at us-west1
kubectl apply -f app-deployment.yaml
kubectl get svc web-app-a-svc --watch
```
External IP assigned: `34.187.230.32` (~2 min).

```bash
curl -v http://34.187.230.32
```
Result: `200 OK`, `Hello, world!`, `Hostname: web-app-a-6d886d95f4-xsdz2`
— confirmed a distinct pod from Cluster 1.

```bash
kubectl get pods
```
Result: all 3 replicas `Running`, `1/1` — full replica count achieved
here, unlike Cluster 1's Standard node-capacity limit.

---

## Outcome

| Deliverable | Status | Notes |
|---|---|---|
| Working cluster(s) with accessible endpoint | ✅ | Two independent clusters, two independent external IPs, both verified via curl |
| Two GKE clusters | ✅ | `bn-observability-poc` (us-central1-a, Standard) + `bn-observability-poc-east` (us-west1, Autopilot) |
| Cross-regional presence | ✅ (geography only) | Different regions confirmed; **not** the same as validated failover — see `architecture.md` §5 for what is and isn't demonstrated |
| Multi-pod deployment | ✅ (Cluster 2 fully; Cluster 1 partially, documented) | 3/3 on Autopilot, 1/3 on single-node Standard |
| Logs queryable in BigQuery | ✅ | Cluster 1 only — see `architecture.md` for scope note on Cluster 2 |
