# Runbook: bootstrap a SolrCloud

Installs the operator stack, creates a SolrCloud, creates a least-privilege Solr user, and optionally connects solr-mcp. Works with no solr-mcp at all.

## Preconditions
- `kubectl` context confirmed by the user (`scripts/preflight.sh` will say "not found" for the SolrCloud, which is expected here).
- `helm` ≥ 3, `jq`, `openssl` on the workstation.
- A StorageClass that can provision the PVC size in the template.

## Steps

1. **Install the CRDs and the Solr Operator.** The `all-with-dependencies.yaml` bundle includes the ZookeeperCluster CRD; the chart installs the zookeeper-operator alongside the Solr Operator by default. Pin the version. *(Commands from the v0.9 "Running the Solr Operator" page; re-check that page for the current version number.)*
   ```
   helm repo add apache-solr https://solr.apache.org/charts && helm repo update
   kubectl create -f https://solr.apache.org/operator/downloads/crds/v0.9.1/all-with-dependencies.yaml
   helm install solr-operator apache-solr/solr-operator --version 0.9.1 -n solr-operator --create-namespace
   ```
   Verify: `kubectl get crd solrclouds.solr.apache.org solrbackups.solr.apache.org zookeeperclusters.zookeeper.pravega.io` and `kubectl get pods -n solr-operator` shows both `solr-operator` and `solr-operator-zookeeper-operator` running.
2. **Optional: cert-manager.** Not required by the operator. Install it only if you will enable `solrTLS` with cert-manager-issued certificates (`runbooks/` do not cover certificate issuance; follow the operator's TLS page).
3. **Create the SolrCloud.** Copy `assets/solrcloud-prod.yaml` (or `-dev.yaml` for kind/minikube), set `metadata.name`, `namespace`, `solrImage.tag`, storage size, and apply. Remind the user: the `pvcTemplate` chosen here is permanent.
   ```
   kubectl apply -f solrcloud-films.yaml
   scripts/wait-ready.sh films search 900
   ```
   Then `scripts/preflight.sh films search` and read the status block. If pods sit in the `setup-zk` initContainer, ZooKeeper isn't up — check `kubectl get zookeepercluster -n search`.
4. **Create the `solr-mcp` Solr user** (capability: create a Solr user; provider: direct as `admin`). The bootstrapped `solr` user is read-only, so an MCP server needs its own identity. Payloads in `assets/solr-mcp-user.json`.
   ```
   scripts/solr-api.sh films search POST admin/authentication --data-binary @set-user.json
   scripts/solr-api.sh films search POST admin/authorization  --data-binary @set-user-role.json
   kubectl create secret generic solr-mcp-creds -n search --type=kubernetes.io/basic-auth \
     --from-literal=username=solr-mcp --from-literal=password="$(openssl rand -base64 24)"
   ```
   Use the same generated password in `set-user.json`; write it to the secret first, then build the JSON from the secret so it is never in a shell history line. Never print it.
5. **Optional: connect solr-mcp** — continue with `runbooks/connect-mcp.md`.

## Verify
- `scripts/preflight.sh films search` shows `ready: N/N`, `upToDate: N`, a `version`, and the bootstrap secret present.
- Capability `list collections` returns an empty list (fresh cluster) via whichever provider preflight chose.

## Rollback
`kubectl delete solrcloud films -n search` removes pods and services; PVCs follow `reclaimPolicy`. State the policy to the user before running it.

Validated against: Solr Operator 0.9.x, Solr 9.x. Install commands checked against the v0.9 "Running the Solr Operator" page on 2026-09-10.
