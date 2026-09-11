# Gotchas

Read before any non-trivial change. Each line says where it comes from.

**Storage**
- `dataStorage.persistent.pvcTemplate` cannot be changed after creation. Resizing storage means a new SolrCloud plus restore (or reindex), not an edit. *(operator ref guide)*
- `reclaimPolicy: Delete` removes PVCs on scale-down and on CR deletion, not when a pod is deleted. `Retain` (documented default) leaves PVCs behind; clean them up deliberately. *(operator ref guide)*
- A PodDisruptionBudget is created by default and is **not shard-aware**. A node drain can evict two replicas of the same shard even though `updateStrategy` would never do that. *(operator ref guide, known issue)*

**Security**
- `security.json` is bootstrapped **once**. After that the operator does not touch it. Changing a password in a Kubernetes Secret does not change it in Solr, and changing it in Solr does not update the Secret — you must do both. *(auth doc)*
- `k8s-oper` is the operator's identity for probes and cluster status. If its password changes in Solr but not in `<name>-solrcloud-basic-auth`, the operator is locked out. Never use this user for anything else. *(auth doc)*
- The bootstrapped `solr` user has the `users` role → `read` only (plus `collection-admin-edit` via the `k8s` role). It cannot index or edit schema. `update`, `security-edit` and `all` belong to `admin`. *(auth doc, default `security.json`)*
- Deleting the bootstrap secret after capturing the admin password is allowed, but triggers a rolling restart because the `setup-zk` initContainer definition changes. *(auth doc)*
- With `probesRequireAuth: false` (default), the probe endpoints `/admin/info/system` and `/admin/info/health` are anonymous. *(auth doc)*

**Rollouts**
- `updateStrategy.method: Managed` (documented default) reads live cluster state and never takes down more than `maxShardReplicasUnavailable` replicas of any shard. That guarantee does nothing for a collection with `replicationFactor: 1` — queries against that shard fail while its only replica restarts. *(managed-updates doc)*
- Changing `solrModules`, `additionalLibs`, `solrOpts`, `solrJavaMem`, TLS secrets (when `restartOnTLSSecretUpdate` is set) or custom pod options triggers a rolling restart. Plan them like upgrades. *(CRD + ref guide)*
- Restarting the operator pod does not restart Solr. Solr restarts come from CR changes or `updateStrategy.restartSchedule`. *(operator behaviour)*

**Backups**
- Backup repositories are declared on the `SolrCloud` (`spec.backupRepositories[]`). Adding one triggers a rolling restart (the pods need the volume or credentials mounted). *(backup doc)*
- A `SolrBackup` names each Solr backup `<SolrBackup name>-<collection>`, uses incremental backups (Solr ≥ 8.9), and keeps `recurrence.maxSaved` points (default 5). Deleting the `SolrBackup` object does not delete backup data. *(backup doc)*
- Solr has no API that lists configured repositories. The `repository` argument must come from the CR. *(Solr Collections API)*

**ZooKeeper**
- With `zookeeperRef.provided`, the zookeeper-operator must be installed separately; the Solr Operator's Helm chart can pull it in as a dependency. Without it, `SolrCloud` never becomes ready and the symptom is Solr pods waiting in the `setup-zk` initContainer. *(running-the-operator doc)*
