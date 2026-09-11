# SolrCloud.status fields

Field names verified against the CRD (`config/crd/bases/solr.apache.org_solrclouds.yaml`, `apache/solr-operator` `main`). Read with `kubectl get solrcloud <name> -n <ns> -o jsonpath='{<path>}'`.

| Field | jsonpath | Use |
|---|---|---|
| ready pods | `{.status.readyReplicas}` | compare with `{.spec.replicas}` |
| total pods | `{.status.replicas}` | |
| pods on current spec | `{.status.upToDateNodes}` | rollout finished when equal to `spec.replicas` |
| running Solr version | `{.status.version}` | |
| version being rolled to | `{.status.targetVersion}` | empty when no upgrade in flight |
| in-cluster Solr URL | `{.status.internalCommonAddress}` | for solr-mcp `SOLR_URL` |
| external URL | `{.status.externalCommonAddress}` | only with `spec.solrAddressability.external` |
| ZooKeeper string | `{.status.zookeeperConnectionInfo.internalConnectionString}` + `{.status.zookeeperConnectionInfo.chroot}` | |
| per-node detail | `{.status.solrNodes[*].name}` with `.ready`, `.version`, `.specUpToDate`, `.nodeName`, `.scheduledForDeletion`, `.internalAddress` | which pod is not ready, not yet upgraded, or draining |
| backup repos available | `{.status.backupRepositoriesAvailable}` | map of repository name → bool |
| pod label selector | `{.status.podSelector}` | for `kubectl get pods -l …` |

One-liners:
```
kubectl get solrcloud films -n search -o jsonpath='{.status.readyReplicas}/{.spec.replicas} upToDate={.status.upToDateNodes} version={.status.version} target={.status.targetVersion}{"\n"}'
kubectl get solrcloud films -n search -o jsonpath='{range .status.solrNodes[*]}{.name}{"\t"}ready={.ready}{"\t"}version={.version}{"\t"}upToDate={.specUpToDate}{"\n"}{end}'
```
