# Runbook: rolling upgrade (change `solrImage.tag`)

The operator does the rollout; this runbook is about making sure it can do it without query gaps, and knowing when it is done.

## Preconditions
- `scripts/preflight.sh <name> <ns>` shows `ready: N/N`, `upToDate: N`, and `target: same` (no rollout already in flight).
- `updateStrategy.method` is `Managed` (documented default). If it is `StatefulSet` or `Manual`, stop and explain: the operator will not drain shard-aware, so this runbook's guarantees do not apply.
- Cluster status (capability: cluster status) shows `healthy: true`.
- **Every collection has `replicationFactor ≥ 2`.** Read it from the cluster-status output (`collections.<name>.replicationFactor`). If any collection has RF 1, state plainly that queries to that collection will fail for the duration of each pod restart, and ask whether to proceed anyway.
- Target Solr version is compatible with the running one (same major, or read the Solr upgrade notes for cross-major).

## Steps

1. Record the current tag for rollback:
   ```
   kubectl get solrcloud films -n search -o jsonpath='{.spec.solrImage.tag}{"\n"}'
   ```
2. Propose the patch; run only after approval:
   ```
   kubectl patch solrcloud films -n search --type merge -p '{"spec":{"solrImage":{"tag":"9.10"}}}'
   ```
3. Watch the rollout. `status.targetVersion` appears, pods restart one `maxPodsUnavailable` batch at a time, `upToDateNodes` climbs:
   ```
   scripts/wait-ready.sh films search 1800
   kubectl get solrcloud films -n search -o jsonpath='{range .status.solrNodes[*]}{.name}{"\t"}ready={.ready}{"\t"}version={.version}{"\n"}{end}'
   ```
   If a pod stays not-ready for more than a few minutes, go to `runbooks/incident.md` — do not patch anything else meanwhile.
4. Confirm the cluster is clean again (capability: cluster status): `healthy: true`, no `issues[]`, and `status.version` equals the new tag.

## Verify
- Cluster status `healthy: true`.
- One representative query per important collection returns results (capability: search or collection health).

## Rollback
Patch `solrImage.tag` back to the recorded value and repeat step 3. The operator rolls back the same way it rolled forward. Note: Solr does not guarantee that an index written by a newer version is readable by an older one across major versions; check before rolling back a cross-major upgrade.

Validated against: Solr Operator 0.9.x (`status.version`, `status.targetVersion`, `status.upToDateNodes`, `status.solrNodes[]` verified in the CRD).
