# Runbook: backup and restore

Two kinds of backup, two providers. Scheduled backups are a `SolrBackup` CR (k8s). One-off backups and all restores go through the Solr API (mcp or direct). Both use the same repository declared on the `SolrCloud`, so backups made one way are visible the other way.

## Preconditions
- The SolrCloud has at least one `spec.backupRepositories[]` entry; preflight lists them under `backups:`. If none, add one first (`assets/solrcloud-prod.yaml` has an S3 example) — that change triggers a rolling restart, so treat it like an upgrade.
- `status.backupRepositoriesAvailable.<name>` is `true`.
- Solr ≥ 8.9 for incremental backups (the operator requires this for `recurrence`).

## Scheduled backups (k8s)

1. Fill in `assets/solrbackup.yaml`: `spec.solrCloud`, `spec.repositoryName`, `spec.collections` (omit to back up all), `spec.recurrence.schedule` (Go cron spec, e.g. `@daily` or `0 2 * * *`), `spec.recurrence.maxSaved`.
2. `kubectl apply -f solrbackup-films.yaml`
3. `kubectl get solrbackup -n search` — columns `STARTED`, `FINISHED`, `SUCCESSFUL`, `NEXTBACKUP`. History is under `status.history`.

Each Solr-side backup is named `<SolrBackup name>-<collection>`; e.g. `SolrBackup nightly` of `films` produces backup `nightly-films`. Pausing: set `spec.recurrence.disabled: true`. Deleting the `SolrBackup` does not delete backup data.

## One-off backup (mcp: `backup-collection` · direct)

```
scripts/solr-api.sh films search GET 'admin/collections?action=BACKUP&name=manual-films&collection=films&repository=nightly-s3&async=bk1&wt=json'
scripts/solr-api.sh films search GET 'admin/collections?action=REQUESTSTATUS&requestid=bk1&wt=json'
```

## List backups (mcp: `list-backups` · direct)

```
scripts/solr-api.sh films search GET 'admin/collections?action=LISTBACKUP&name=nightly-films&repository=nightly-s3&wt=json'
```
Output lists backup points with `backupId`, timestamps, and index size.

## Restore (mcp: `restore-collection` · direct)

Always into a collection that does not exist yet, then swap an alias. Never restore over the live collection.

1. Confirm the target name is free (capability: list collections).
2. Propose; run after approval:
   ```
   scripts/solr-api.sh films search GET 'admin/collections?action=RESTORE&name=nightly-films&collection=films_restored&repository=nightly-s3&async=rs1&wt=json'
   scripts/solr-api.sh films search GET 'admin/collections?action=REQUESTSTATUS&requestid=rs1&wt=json'
   ```
   Add `&backupId=<n>` to restore a specific point from LISTBACKUP.
3. Verify doc count (capability: collection stats) against expectations.
4. If this restore replaces the live data: `CREATEALIAS name=films collections=films_restored` — only if `films` is already an alias, not a collection. If `films` is a real collection, the swap needs a rename step; plan it in `runbooks/reindex.md` terms and get approval for each destructive step.

## Verify
- Backup: LISTBACKUP shows the new point.
- Restore: cluster status `healthy: true`; `films_restored` reachable; counts match.

## Rollback
Restore created a new collection, so rollback is deleting it (`DELETE` in the cheatsheet), with approval.

Validated against: Solr Operator 0.9 backup docs (naming, `maxSaved` default 5, incremental ≥ 8.9); `status.backupRepositoriesAvailable` verified in the CRD.
