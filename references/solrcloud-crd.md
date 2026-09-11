# SolrCloud spec — the fields you will actually set

Field names verified against the CRD on `apache/solr-operator` `main`. Defaults marked "documented" come from the v0.9 reference guide, not the CRD schema; confirm with `kubectl explain solrcloud.spec.<field>` when it matters. Reference: https://solr.apache.org/guide/operator/latest/solr-cloud/solr-cloud-crd.html

| Field | Purpose | Default | Change when |
|---|---|---|---|
| `replicas` | number of Solr pods | 3 (documented) | scaling — `runbooks/scale.md` |
| `solrImage.repository` / `.tag` | Solr image | `solr` / operator-dependent | upgrading — `runbooks/rolling-upgrade.md` |
| `zookeeperRef.provided` / `.connectionInfo` | operator-managed ZK (via zookeeper-operator) or external | provided | bring-your-own ZK |
| `dataStorage.persistent.pvcTemplate` | PVC size/class | ephemeral if unset | **set once; immutable afterwards** |
| `dataStorage.persistent.reclaimPolicy` | keep or delete PVCs on scale-down / CR delete | `Retain` (documented) | check before any delete |
| `updateStrategy.method` | `Managed` (shard-aware), `StatefulSet`, `Manual` | `Managed` (documented) | almost never |
| `updateStrategy.managed.maxPodsUnavailable` | rollout parallelism | 25% (documented) | large clusters |
| `updateStrategy.managed.maxShardReplicasUnavailable` | per-shard safety | 1 (documented) | never below 1 |
| `updateStrategy.restartSchedule` | cron for periodic restarts | none | routine JVM restarts |
| `scaling.vacatePodsOnScaleDown` | move replicas off pods before deleting them | `true` (CRD default) | leave on |
| `scaling.populatePodsOnScaleUp` | balance replicas onto new pods | `true` (CRD default) | leave on |
| `solrSecurity.authenticationType: Basic` | bootstrap `security.json` with `admin`/`solr`/`k8s-oper` | none | always in production |
| `solrSecurity.basicAuthSecret` | operator's credentials when you supply your own `security.json` | — | custom security |
| `solrSecurity.bootstrapSecurityJson` | your own `security.json` Secret | — | custom security |
| `solrTLS.pkcs12Secret`, `.trustStoreSecret`, `.keyStorePasswordSecret` | server TLS | none | production |
| `solrAddressability.commonServicePort` / `.podPort` | service and pod ports | 80 / 8983 (documented) | rarely |
| `solrAddressability.external` | ingress / external DNS | none | client access from outside the cluster |
| `backupRepositories[]` | named repos: `s3{region,bucket,baseLocation,credentials,endpoint,proxyUrl}`, `gcs{bucket,baseLocation,gcsCredentialSecret}`, `volume{source,directory}` | none | before any backup; `name` is the `repository` argument everywhere |
| `solrModules` / `additionalLibs` | extra modules / jars | none | note: triggers a rolling restart |
| `solrJavaMem`, `solrOpts`, `solrGCTune` | JVM settings | operator defaults | OOM, GC tuning |
| `customSolrKubeOptions.podOptions.resources` | pod requests/limits | none | OOMKilled, scheduling pressure |
| `availability.podDisruptionBudget` | PDB | enabled (documented) | rarely; it is not shard-aware |
