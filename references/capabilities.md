# Capabilities → providers

Every runbook step names a *capability*, not a tool. `scripts/preflight.sh` resolves each capability to one provider for this session, in this order of preference:

1. **mcp** — the named solr-mcp tool appears in `tools/list`
2. **direct** — `scripts/solr-api.sh` (curl inside `<name>-solrcloud-0`, credentials from the bootstrap secret, password on stdin)
3. **k8s** — `kubectl` against the `SolrCloud` / `SolrBackup` CR; infrastructure only, never a fallback for anything Solr-side

An old solr-mcp (the 11 tools on `main` as of 2026-09) resolves search/index/schema/collection capabilities to `mcp` and the rest to `direct`. No solr-mcp at all resolves everything Solr-side to `direct`. Runbooks read identically either way.

| Capability | mcp tool | direct (`solr-api.sh <name> <ns> …`) | k8s |
|---|---|---|---|
| list collections | `list-collections` | `GET admin/collections?action=LIST` | — |
| collection health | `check-health` | `GET <coll>/admin/ping` | — |
| cluster status (`healthy`, `issues[]`) | `get-cluster-status` *(solr-mcp issue #3)* | `scripts/cluster-status.sh` | node readiness only: `status.solrNodes[].ready` |
| list configsets | `list-configsets` *(#3)* | `GET admin/configs?action=LIST` | — |
| create collection | `create-collection` | `GET admin/collections?action=CREATE&name=…&numShards=…&replicationFactor=…&collection.configName=…` | — |
| schema read | `get-schema` | `GET <coll>/schema` | — |
| schema add fields / types | `add-fields`, `add-field-types` | `POST <coll>/schema` with `{"add-field":[…]}` / `{"add-field-type":[…]}` | — |
| index documents | `index-json-documents` etc. | `POST <coll>/update?commit=true` JSON array | — |
| search | `search` | `GET <coll>/select?q=…` | — |
| collection stats | `get-collection-stats` | `GET <coll>/select?q=*:*&rows=0` (numFound) | — |
| aliases | `create-alias`, `list-aliases`, `delete-alias` *(PR #159)* | `GET admin/collections?action=CREATEALIAS\|LISTALIASES\|DELETEALIAS` | — |
| one-off backup | `backup-collection` *(#4)* | `GET admin/collections?action=BACKUP&name=…&collection=…&repository=…` | — |
| list backups | `list-backups` *(#4)* | `GET admin/collections?action=LISTBACKUP&name=…&repository=…` | — |
| restore | `restore-collection` *(#4)* | `GET admin/collections?action=RESTORE&name=…&collection=<new>&repository=…` | — |
| scheduled backups | — | — | `SolrBackup` CR |
| scale, upgrade, restart, storage, TLS, auth | — | — | edit `SolrCloud` CR |
| create a Solr user | — | `POST admin/authentication` + `admin/authorization` (as `admin`) | store in a `kubernetes.io/basic-auth` Secret |

Rules:
- Prefer `mcp` when available: typed responses, behaviour hints, and the client's permission model apply.
- `direct` is complete, not degraded. Every runbook is executable with it alone.
- `k8s` is never a fallback for a Solr-side capability, and Solr-side providers are never used for infrastructure.
- Restore, in either provider, targets a collection that does not exist yet.
