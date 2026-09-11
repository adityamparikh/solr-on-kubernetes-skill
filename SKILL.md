---
name: solr-on-kubernetes
description: Deploy and operate Apache Solr on Kubernetes with the Solr Operator, with or without the Solr MCP server (solr-mcp). Use this whenever the user mentions SolrCloud or SolrBackup resources, the Solr Operator, running Solr on k8s/EKS/GKE/AKS/kind, upgrading or scaling Solr pods, rolling restarts, a Solr pod in CrashLoopBackOff, a replica stuck recovering, Solr backups on Kubernetes, or connecting solr-mcp to a cluster — even if they don't say "operator". Do not use for standalone or Docker Solr, or for plain query, index and schema work on a healthy cluster that is already connected.
---

# Solr on Kubernetes

Solr on Kubernetes has two layers with different owners. The **Solr Operator** owns infrastructure — pods, ZooKeeper, TLS, basic auth, rolling restarts, scaling, scheduled backups — and is driven entirely by editing `SolrCloud` and `SolrBackup` custom resources. Everything **inside Solr** — collections, schema, documents, aliases, one-off backups, cluster status — is reached through the Solr HTTP API, either via solr-mcp tools when they are available or directly via `scripts/solr-api.sh` when they are not.

Most mistakes on this platform come from crossing that line: creating a collection by editing YAML, or scaling the cluster with the Collections API. The routing table below exists to stop that.

## Step 1 — Preflight, every time

Run `scripts/preflight.sh <solrcloud-name> [namespace]` before reading any runbook or proposing any command. It prints the kube context and namespace, a summary of the `SolrCloud` spec and status, and which solr-mcp tools are reachable. Restate the context and namespace to the user and get confirmation before acting — acting on the wrong cluster is the one mistake nothing else here can undo.

Preflight also prints a **capability map**: for each thing the runbooks need (cluster status, backups, aliases, …), whether it will be served by an solr-mcp tool, by the direct script, or by `kubectl`. Use that map for the rest of the session. Details in `references/capabilities.md`.

If the user has not given a SolrCloud name, run `kubectl get solrcloud -A` and ask which one.

## Step 2 — Route the request

| The user wants to… | Do this | Not this |
|---|---|---|
| change replica count, Solr version, storage, TLS, auth config; restart pods | Edit the `SolrCloud` CR following the matching runbook | Collections API, solr-mcp |
| create/modify collections, schema, documents, aliases | solr-mcp tool if the capability map says so, else `scripts/solr-api.sh` | Editing YAML |
| know whether the cluster is healthy | `get-cluster-status` tool → else `scripts/cluster-status.sh` → then `kubectl get solrcloud -o yaml` and pod logs | Inferring from pod phase alone |
| recurring backups | `SolrBackup` CR (`assets/solrbackup.yaml`) | Ad-hoc BACKUP calls |
| one-off backup or restore | `backup-collection` / `restore-collection` tools → else `scripts/solr-api.sh` | `SolrBackup` CR |
| reindex a collection | `plan-reindex` prompt if present → else `references/runbooks/reindex.md` | Anything on the Kubernetes side |
| connect solr-mcp to this cluster | `references/runbooks/connect-mcp.md` | Hand-typing URLs and secrets |

## Step 3 — Follow the runbook

Read only the one that matches. Each has preconditions, steps with the exact command for each provider, a verification step, and a rollback.

- `references/runbooks/bootstrap.md` — install the operator, create a SolrCloud, optionally connect solr-mcp
- `references/runbooks/connect-mcp.md` — wire solr-mcp to an existing SolrCloud
- `references/runbooks/rolling-upgrade.md` — change `solrImage.tag` without query gaps
- `references/runbooks/scale.md` — add or remove Solr pods with replica migration
- `references/runbooks/backup-restore.md` — scheduled and one-off backups, restore
- `references/runbooks/reindex.md` — blue/green reindex behind an alias
- `references/runbooks/incident.md` — start here when something is broken

## Safety rules

These hold in every runbook.

- Destructive `kubectl` operations — `delete`, lowering `replicas`, changing `solrImage.tag` — are proposed with the exact command and run only after the user approves in the same turn. Reads are fine without asking.
- Never `kubectl delete solrcloud` without first stating the current `spec.dataStorage.persistent.reclaimPolicy` and what it means for the data.
- Never propose editing `spec.dataStorage.persistent.pvcTemplate`; it is immutable after creation. Storage changes mean a new cluster plus restore.
- Before any upgrade or restart, check that every collection has `replicationFactor >= 2`. With a single replica a managed rolling update still causes query gaps; say so explicitly.
- Passwords never appear in output and never as command-line arguments. `scripts/solr-api.sh` reads the password from the bootstrap secret and passes it to `curl` on stdin. When the user needs a password, print the `kubectl get secret … | base64 -d` command for them to run.
- Restore only into a collection that does not exist yet; then swap an alias. This matches what solr-mcp enforces.
- Never use the `k8s-oper` user. It is the operator's probe identity; if its password rotates the operator locks itself out.

## Reference files

- `references/capabilities.md` — the capability → provider table; how the map is resolved
- `references/naming-conventions.md` — services, secrets and pod names the operator creates
- `references/status-fields.md` — the `SolrCloud.status` fields and jsonpath for each
- `references/solrcloud-crd.md` — the spec fields you will actually set, with defaults and when to change them
- `references/solr-api-cheatsheet.md` — the exact Solr API calls used in direct mode
- `references/gotchas.md` — the operator behaviours that bite; read before any non-trivial change

Validated against: Solr Operator v0.9.x CRDs (field names checked against `main`), Solr 9.x/10.x, solr-mcp `main` as of 2026-09 (11 tools). Runbook steps that need solr-mcp tools not yet released carry a `requires:` note and always have a direct-mode alternative.
