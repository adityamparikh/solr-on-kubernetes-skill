# Runbook: incident triage

Start with `scripts/preflight.sh` and cluster status (capability: cluster status). Then pick the branch that matches the symptom. Each branch names the diagnostic, the likely causes in order, and whether the remedy may be proposed automatically or needs a human decision first. Reads are free; every remedy is proposed, not run.

## Symptom: cluster status `healthy: false`, replicas `recovering` or `down`, all nodes live

Diagnostic: `issues[]` — which collection/shard/replica/node; `kubectl logs <pod> -n <ns> -c solrcloud-node --since=15m | grep -iE 'recover|error'`.

1. **A rollout just happened** (preflight shows `target:` set or `upToDate < replicas`): recovery after restart is normal for minutes, longer for large indexes. Wait, re-check. Remedy: none.
2. **Recovery stuck > 15 min, node live, leader present**: usually a replica that cannot catch up (tlog replay, disk full). Check `df` on that pod. Remedy (propose): `kubectl delete pod <pod> -n <ns>` — safe only when `updateStrategy.method` is `Managed`, one pod at a time, and only if the shard has another active replica. State that condition.
3. **No leader for the shard**: all replicas down or in recovery. Do not delete anything. Check ZooKeeper (below) first; leader election needs ZK.

## Symptom: node not in `liveNodes`, pod `Running` and ready

Solr lost its ZooKeeper session. Diagnostic: `kubectl get zookeepercluster -n <ns>`, `kubectl get pods -n <ns> -l app=<name>-solrcloud-zookeeper`; Solr log for `ZooKeeper session expired`. Remedy: fix ZK first (branch below); Solr reconnects on its own. Deleting Solr pods here makes it worse.

## Symptom: Solr pod `CrashLoopBackOff` or stuck in `Init`

Diagnostic: `kubectl describe pod <pod> -n <ns>`; `kubectl logs <pod> -n <ns> -c solrcloud-node --previous`; for `Init`, `kubectl logs <pod> -c setup-zk` (initContainer name from `describe`).

1. **Stuck in `setup-zk`**: ZooKeeper unreachable — zookeeper-operator not installed, or ZK cluster not ready. Check `kubectl get zookeepercluster`.
2. **`PersistentVolumeClaim … no space` / `No space left on device`**: PVC full. Storage cannot be resized in place (`pvcTemplate` immutable). Remedy is a human decision: delete data (DELETE collection with approval), or new cluster + restore.
3. **Bad custom `solr.xml`** (`customSolrKubeOptions` or `solrModules` change just made): log shows parse error. Remedy (propose): revert the CR change; the operator rolls back.
4. **`OOMKilled` in `describe`**: heap exceeds container limit. Remedy (propose a CR edit, after approval): raise `customSolrKubeOptions.podOptions.resources.limits.memory` and set `solrJavaMem` to about half of it; this triggers a rolling restart.
5. **Image pull errors**: wrong `solrImage.tag` or missing `imagePullSecret`. Remedy (propose): patch the tag back.

## Symptom: ZooKeeper quorum lost (ZK pods not ready, Solr logs `KeeperErrorCode = ConnectionLoss`)

Diagnostic: `kubectl get pods -n <ns> -l app=<name>-solrcloud-zookeeper -o wide`; `kubectl logs` of a ZK pod. Common causes: PVC or node problems on ZK pods; an unlucky drain took two of three. Remedy: restore quorum — reschedule the ZK pods (node issues) or restore their PVCs. Never delete Solr pods or edit the SolrCloud while quorum is down; everything Solr does depends on it.

## Symptom: disk pressure, no crash yet

Diagnostic: `kubectl exec <pod> -n <ns> -c solrcloud-node -- df -h /var/solr/data` on each pod; collection stats for index sizes. Remedy: this is a capacity decision for the human — scale out (adds nodes; with `populatePodsOnScaleUp` replicas rebalance, spreading disk use), delete unused collections, or plan a migration to bigger PVCs.

## Symptom: operator not reconciling (CR edited, nothing happens)

Diagnostic: `kubectl logs -n solr-operator deploy/solr-operator --since=10m`; `kubectl get events -n <ns> --sort-by=.lastTimestamp | tail -20`. Causes: operator pod down; webhook rejecting the change (message in `kubectl apply` output); CRD version mismatch after an operator upgrade. Remedy: usually restart the operator pod (safe — it does not restart Solr) or fix the rejected field.

## When solr-mcp is the thing that is broken

`401` in solr-mcp logs → wrong user or password (check the Secret key matches the user; remember `solr` cannot write). `Connection refused` → wrong `SOLR_URL` or port (compare with `status.internalCommonAddress`). `PKIX path building failed` → TLS trust missing (solr-mcp issue #2). None of these are Solr-side problems; do not touch the SolrCloud.

Validated against: Solr Operator 0.9 behaviours documented in the reference guide; container/initContainer names from operator source.
