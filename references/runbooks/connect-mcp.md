# Runbook: connect solr-mcp to an existing SolrCloud

Produces a working solr-mcp deployment pointed at the SolrCloud, with credentials sourced from a Secret and no password ever pasted anywhere.

## Preconditions
- `scripts/preflight.sh <name> <ns>` shows `ready: N/N`.
- A published solr-mcp container image (`apache/solr-mcp` — check the tag the project currently publishes; see `apache/solr-mcp` release workflow).
- Decided which Solr user solr-mcp runs as: `admin` (simplest) or the `solr-mcp` user from `runbooks/bootstrap.md` step 4 (least privilege, recommended). The bootstrapped `solr` user will not work for indexing or schema changes.
- If `solrTLS` is set on the SolrCloud: solr-mcp must trust the CA that signed the Solr certificate. As of solr-mcp `main` (2026-09) there is no TLS trust setting (issue #2). Until it lands, run solr-mcp against `http://` only, or mount the CA into the JVM's default truststore in the image.

## Steps

1. **Derive the connection settings from the CR** — never hand-type them.
   ```
   scripts/mcp-values-from-cr.sh films search admin      # or: films search solr-mcp
   ```
   The output is Helm values (for the chart proposed in solr-mcp issue #7) plus the equivalent environment for a plain Deployment. It prints the command to *view* the password; do not run that in chat.
2. **Deploy.** Until the chart exists, apply `assets/solr-mcp-deployment.yaml` after filling in the image tag, `SOLR_URL`, and the Secret reference from step 1. Keep `PROFILES=http`; `stdio` makes no sense in a pod. Set `OAUTH2_ISSUER_URI` or, for a cluster-internal test only, disable HTTP security per the solr-mcp docs.
   ```
   kubectl apply -f solr-mcp-deployment.yaml
   kubectl -n search rollout status deploy/solr-mcp
   ```
3. **Verify the server can reach Solr.** Port-forward and list tools, then call `list-collections`:
   ```
   kubectl -n search port-forward svc/solr-mcp 8080:8080 &
   SOLR_MCP_URL=http://localhost:8080/mcp scripts/preflight.sh films search
   ```
   Preflight's capability map now shows `mcp:` for the tools the server has. If it shows "unreachable", check the pod log for `401` (wrong user/password), `Connection refused` (wrong `SOLR_URL` or port), or `PKIX` (TLS trust).
4. **Expose it** (optional): an Ingress in front of `svc/solr-mcp` with TLS, and OAuth enabled. Never expose an unauthenticated MCP endpoint outside the cluster.

## Verify
- `list-collections` via the MCP client returns the same list as `scripts/solr-api.sh films search GET 'admin/collections?action=LIST&wt=json'`.
- If using the `solr-mcp` user: `create-collection` and `add-fields` succeed; with the bootstrapped `solr` user they return 403 — that is the expected failure mode, not a bug.

## Rollback
`kubectl -n search delete deploy/solr-mcp svc/solr-mcp`. Nothing on the Solr side changes.

Validated against: solr-mcp `main` 2026-09 (config: `SOLR_URL`, `SOLR_USERNAME`, `SOLR_PASSWORD`, `PROFILES`, `OAUTH2_ISSUER_URI`).
