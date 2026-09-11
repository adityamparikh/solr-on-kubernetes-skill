# Runbook: scale a SolrCloud

Scaling is a CR edit. The operator moves replicas; the runbook makes sure that happens and that nothing is left under-replicated.

## Preconditions
- Preflight shows `ready: N/N`, no rollout in flight, cluster status `healthy: true`.
- Preflight's `scaling:` line shows `vacatePodsOnScaleDown=true` and `populatePodsOnScaleUp=true` (CRD defaults). If either is `false`, scaling down will delete pods with replicas still on them, and scaling up will add empty pods — explain this before proceeding.
- For scale-down: the remaining pods can hold all replicas (count replicas per node in cluster-status `collections` and compare with disk/heap headroom on the survivors).

## Scale up

1. Propose; run after approval:
   ```
   kubectl patch solrcloud films -n search --type merge -p '{"spec":{"replicas":5}}'
   ```
2. `scripts/wait-ready.sh films search 900`.
3. Cluster status: `liveNodes` includes the new pods. With `populatePodsOnScaleUp: true` the operator balances replicas onto them via Solr's replica balancing; give it a few minutes, then re-check that the new nodes host replicas. If they stay empty, that is worth an operator log check (`kubectl logs -n solr-operator deploy/solr-operator`), not a manual MOVEREPLICA.

## Scale down

1. State which pods will go: StatefulSet ordering removes the highest ordinals first (`films-solrcloud-4`, then `-3`, …). List the replicas on those pods from cluster status.
2. Propose; run after approval:
   ```
   kubectl patch solrcloud films -n search --type merge -p '{"spec":{"replicas":3}}'
   ```
3. Watch `status.solrNodes[]` — departing pods get `scheduledForDeletion: true` while the operator vacates them. `scripts/wait-ready.sh films search 1800`.
4. Cluster status `healthy: true`, `issues[]` empty, and every collection still has its full `replicationFactor` on the remaining nodes.

## Verify
- `kubectl get pods -n search -l "$(kubectl get solrcloud films -n search -o jsonpath='{.status.podSelector}')"` shows exactly `spec.replicas` pods.
- PVCs of removed pods: with `reclaimPolicy: Retain` they remain and will be reused on the next scale-up; with `Delete` they are gone. Say which applies.

## Rollback
Patch `replicas` back. Scale-up after a scale-down with `Retain` reattaches the old PVCs.

Validated against: Solr Operator 0.9.x (`spec.scaling` defaults and `status.solrNodes[].scheduledForDeletion` verified in the CRD).
