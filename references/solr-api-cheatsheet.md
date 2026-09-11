# Solr API cheatsheet for direct mode

All calls go through `scripts/solr-api.sh <name> <ns> <METHOD> '<path>' [curl args]`. Paths are relative to `/solr/`. Add `&wt=json` where the default isn't JSON. Collections API reference: https://solr.apache.org/guide/solr/latest/deployment-guide/collection-management.html

```
# cluster
GET  admin/collections?action=CLUSTERSTATUS&wt=json
GET  admin/collections?action=LIST&wt=json
GET  admin/configs?action=LIST&wt=json
GET  admin/info/system?wt=json                          # version, JVM; anonymous by default

# collection lifecycle
GET  admin/collections?action=CREATE&name=films_v2&numShards=2&replicationFactor=2&collection.configName=films&wt=json
GET  admin/collections?action=DELETE&name=films_v1&wt=json      # only in reindex.md after alias swap, with approval

# health and size
GET  films/admin/ping?wt=json
GET  films/select?q=*:*&rows=0&wt=json                   # .response.numFound

# schema
GET  films/schema?wt=json
POST films/schema --data-binary @add-field.json          # {"add-field":[{"name":"year","type":"pint","stored":true}]}
POST films/schema --data-binary @add-type.json           # {"add-field-type":[…]}

# indexing
POST films/update?commit=true --data-binary @docs.json   # JSON array of documents

# aliases
GET  admin/collections?action=CREATEALIAS&name=films&collections=films_v2&wt=json
GET  admin/collections?action=LISTALIASES&wt=json
GET  admin/collections?action=DELETEALIAS&name=films&wt=json

# backup / restore (repository = SolrCloud.spec.backupRepositories[].name)
GET  admin/collections?action=BACKUP&name=manual-films&collection=films&repository=nightly-s3&wt=json
GET  admin/collections?action=LISTBACKUP&name=nightly-films&repository=nightly-s3&wt=json
GET  admin/collections?action=RESTORE&name=nightly-films&collection=films_restored&repository=nightly-s3&wt=json
#   add &backupId=<n> to restore a specific point; add &async=<id> for long operations, then
GET  admin/collections?action=REQUESTSTATUS&requestid=<id>&wt=json

# security (as admin only) — payloads in assets/solr-mcp-user.json
POST admin/authentication --data-binary @set-user.json
POST admin/authorization  --data-binary @set-user-role.json
```

Notes
- `solr-api.sh` inlines a single `--data-binary @file` into the curl config it streams to the pod; for multiple files, call it once per file.
- Operator-created backups are named `<SolrBackup name>-<collection>`; use that as `name` in LISTBACKUP/RESTORE.
- Long-running BACKUP/RESTORE should use `async` and REQUESTSTATUS; the in-pod curl has no special timeout but `kubectl exec` sessions can drop.
