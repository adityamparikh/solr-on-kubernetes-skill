# solr-on-kubernetes

An agent skill for operating Apache Solr on Kubernetes with the [Solr Operator](https://solr.apache.org/operator/), with or without the [Solr MCP server](https://github.com/apache/solr-mcp).

It gives an agent (Claude Code, Claude Desktop, or any host that supports skills) the procedures the Solr Operator does not put in tool descriptions: what to check before acting, which layer a change belongs to, how to upgrade or scale without query gaps, and how to triage a broken cluster.

## How it works

- **`SKILL.md`** is the router: mandatory preflight, a routing table (infrastructure → `kubectl` on the CR; data → Solr API), safety rules, and an index.
- **`scripts/preflight.sh`** prints the kube context, a `SolrCloud` spec/status summary, and a *capability map* saying whether each operation is served by an solr-mcp tool, by `scripts/solr-api.sh` (curl inside a Solr pod, password on stdin), or by `kubectl`.
- **`references/runbooks/`** — bootstrap, connect-mcp, rolling-upgrade, scale, backup-restore, reindex, incident. Each step names a capability, so the same runbook works with a full solr-mcp, an older one, or none.
- **`references/`** — CRD fields, status jsonpaths, naming conventions, gotchas, and a direct-mode API cheatsheet.
- **`assets/`** — `SolrCloud` / `SolrBackup` templates, a plain solr-mcp Deployment, and Security API payloads for a least-privilege `solr-mcp` user.

Field names and resource names were checked against the operator's CRDs and source on `main` (2026-09). Defaults that exist only in the reference guide are labelled "documented".

## Install

Copy or clone this repository into your host's skills directory, or package it with skill-creator's `package_skill.py` and install the resulting `.skill` file.

## Status

Scripts are shellcheck-clean and tested against a stubbed `kubectl` and MCP server. The runbooks have **not** yet been run end to end against a real cluster; `evals/evals.json` lists the scenarios to validate on a `kind` cluster with the operator installed.
