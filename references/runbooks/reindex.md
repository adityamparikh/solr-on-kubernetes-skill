# Runbook: reindex a collection (blue/green behind an alias)

Nothing here touches Kubernetes. If solr-mcp exposes the `plan-reindex` prompt (issue #5), use it — it encodes exactly this sequence. Otherwise follow the steps with the provider preflight chose.

## Preconditions
- Cluster status `healthy: true`.
- Disk headroom for a second copy of the collection on each node (compare index size from collection stats with PVC free space: `kubectl exec films-solrcloud-0 -n search -c solrcloud-node -- df -h /var/solr/data`).
- Know whether clients reach the collection by its real name or by an alias. If by real name, the final swap is a two-step alias creation (below) and clients must be told; if by alias, the swap is atomic.

## Steps

1. **Read the current schema** (capability: schema read) and the configset it uses (from cluster status: `collections.films.configName` if present, else `admin/collections?action=CLUSTERSTATUS` raw).
2. **Optional backup first** (`runbooks/backup-restore.md`, one-off).
3. **Create the new collection** (capability: create collection) — `films_v2`, same `numShards`/`replicationFactor` unless the reindex is also a re-shard, and either the same configset or a new one prepared in advance.
4. **Apply schema changes** to `films_v2` (capability: schema add fields/types). Never change the live collection's schema during a reindex.
5. **Index** into `films_v2` (capability: index documents). Source is the user's system of record, not the old Solr collection, unless they explicitly want a Solr-to-Solr copy — Solr cannot be relied on to hold every field stored.
6. **Compare counts** (capability: collection stats) between `films` and `films_v2`; run one or two known queries against both.
7. **Swap.** Propose; run after approval:
   - If `films` is an alias: `CREATEALIAS name=films collections=films_v2` (upsert, atomic).
   - If `films` is a real collection: clients must move to an alias. Create `films_current → films_v2`, tell the user to repoint clients, and leave `films` untouched until they confirm.
8. **Old collection**: leave it in place. Deleting `films_v1` is a separate, explicitly approved step (`DELETE` in the cheatsheet), ideally a day later.

## Verify
- Queries via the alias hit `films_v2` (check `collection` in a debug response, or `LISTALIASES`).
- Cluster status still `healthy: true`.

## Rollback
Point the alias back at the previous collection. That is the whole point of doing it this way.

Validated against: Solr Collections API (CREATEALIAS upsert semantics); no operator interaction.
