#!/usr/bin/env bash
# preflight.sh — run before any Solr-on-Kubernetes operation.
#
# Usage: preflight.sh <solrcloud-name> [namespace] [solr-mcp-url]
#
# Prints: kube context/namespace, operator version, SolrCloud spec + status
# summary, backup repositories, and a capability map that says whether each
# capability is served by an solr-mcp tool, by scripts/solr-api.sh, or by
# kubectl. Never prints a password.
#
# Env:
#   SOLR_MCP_URL   base URL of a running solr-mcp in HTTP mode (optional;
#                  third positional argument overrides). If unset, the map
#                  resolves everything Solr-side to "direct".
#   SOLR_MCP_TOKEN bearer token if solr-mcp has OAuth enabled (optional).
set -euo pipefail

NAME="${1:?usage: preflight.sh <solrcloud-name> [namespace] [solr-mcp-url]}"
NS="${2:-$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null)}"
NS="${NS:-default}"
MCP_URL="${3:-${SOLR_MCP_URL:-}}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing dependency: $1" >&2; exit 2; }; }
need kubectl; need jq

echo "== context"
echo "context:   $(kubectl config current-context)"
echo "namespace: $NS"

echo "== operator"
if kubectl get crd solrclouds.solr.apache.org >/dev/null 2>&1; then
  OPIMG=$(kubectl get deploy -A -o json 2>/dev/null \
    | jq -r '.items[].spec.template.spec.containers[].image | select(test("solr-operator"))' | head -1)
  echo "crds:      present"
  echo "image:     ${OPIMG:-<not found — operator may run outside this cluster or under another name>}"
else
  echo "crds:      MISSING — the Solr Operator is not installed in this cluster"
fi

echo "== SolrCloud/$NAME"
if ! CR=$(kubectl get solrcloud "$NAME" -n "$NS" -o json 2>/dev/null); then
  echo "not found in namespace $NS. Available:"
  kubectl get solrcloud -A 2>/dev/null || true
  exit 1
fi

j() { echo "$CR" | jq -r "$1"; }

REPLICAS=$(j '.spec.replicas // "?"')
TAG=$(j '.spec.solrImage.tag // "?"')
REPO=$(j '.spec.solrImage.repository // "solr"')
METHOD=$(j '.spec.updateStrategy.method // "Managed (default)"')
MPU=$(j '.spec.updateStrategy.managed.maxPodsUnavailable // "25% (documented default)"')
MSRU=$(j '.spec.updateStrategy.managed.maxShardReplicasUnavailable // "1 (documented default)"')
AUTH=$(j '.spec.solrSecurity.authenticationType // "none"')
AUTHSECRET=$(j '.spec.solrSecurity.basicAuthSecret // ""')
TLS=$(j 'if .spec.solrTLS then "yes" else "no" end')
RECLAIM=$(j '.spec.dataStorage.persistent.reclaimPolicy // (if .spec.dataStorage.ephemeral then "ephemeral" else "Retain (default)" end)')
PORT=$(j '.spec.solrAddressability.commonServicePort // 80')
VACATE=$(j '.spec.scaling.vacatePodsOnScaleDown // true')
POPULATE=$(j '.spec.scaling.populatePodsOnScaleUp // true')

echo "image:     $REPO:$TAG"
echo "replicas:  $REPLICAS"
echo "update:    method=$METHOD maxPodsUnavailable=$MPU maxShardReplicasUnavailable=$MSRU"
echo "scaling:   vacatePodsOnScaleDown=$VACATE populatePodsOnScaleUp=$POPULATE"
echo "auth:      $AUTH${AUTHSECRET:+ (user-provided secret: $AUTHSECRET)}"
echo "tls:       $TLS"
echo "storage:   reclaimPolicy=$RECLAIM"
echo "service:   $NAME-solrcloud-common:$PORT (in-cluster)"
echo "backups:   repositories=[$(j '[.spec.backupRepositories[]?.name] | join(", ")')]"

echo "== status"
echo "ready:     $(j '.status.readyReplicas // 0')/$(j '.status.replicas // .spec.replicas // "?"')"
echo "upToDate:  $(j '.status.upToDateNodes // 0')"
echo "version:   $(j '.status.version // "?"') (target: $(j '.status.targetVersion // "same"'))"
echo "address:   $(j '.status.internalCommonAddress // "<none yet>"')"
echo "zk:        $(j '.status.zookeeperConnectionInfo.internalConnectionString // "?"')$(j '.status.zookeeperConnectionInfo.chroot // ""')"
NOTREADY=$(j '[.status.solrNodes[]? | select(.ready != true) | .name] | join(", ")')
[ -n "$NOTREADY" ] && echo "not ready: $NOTREADY"

echo "== secrets (names only)"
for s in "$NAME-solrcloud-security-bootstrap" "$NAME-solrcloud-basic-auth" ${AUTHSECRET:+"$AUTHSECRET"}; do
  if kubectl get secret "$s" -n "$NS" >/dev/null 2>&1; then
    echo "present:   $s (keys: $(kubectl get secret "$s" -n "$NS" -o json | jq -r '.data | keys | join(",")'))"
  fi
done

echo "== solr-mcp"
TOOLS=""
if [ -n "$MCP_URL" ]; then
  AUTHH=()
  [ -n "${SOLR_MCP_TOKEN:-}" ] && AUTHH=(-H "Authorization: Bearer $SOLR_MCP_TOKEN")
  # Streamable HTTP: initialize, then tools/list. Session header is echoed back if the server uses one.
  INIT=$(curl -s -m 5 -D - "${AUTHH[@]}" -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"preflight","version":"0"}}}' \
    "$MCP_URL" 2>/dev/null || true)
  SID=$(printf '%s' "$INIT" | tr -d '\r' | awk -F': ' 'tolower($1)=="mcp-session-id"{print $2}' | head -1)
  SIDH=(); [ -n "$SID" ] && SIDH=(-H "Mcp-Session-Id: $SID")
  LIST=$(curl -s -m 5 "${AUTHH[@]}" "${SIDH[@]}" -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' "$MCP_URL" 2>/dev/null || true)
  # Response may be plain JSON or an SSE "data:" line.
  TOOLS=$(printf '%s' "$LIST" | sed -n 's/^data: //p; /^{/p' | jq -r '.result.tools[]?.name' 2>/dev/null | sort -u | tr '\n' ' ' || true)
  if [ -n "$TOOLS" ]; then
    echo "reachable: $MCP_URL"
    echo "tools:     $TOOLS"
  else
    echo "unreachable or no tools listed at $MCP_URL — resolving Solr-side capabilities to direct"
  fi
else
  echo "not configured (set SOLR_MCP_URL or pass it as 3rd argument) — resolving Solr-side capabilities to direct"
fi

has() { [[ " $TOOLS " == *" $1 "* ]]; }
cap() { # cap <capability> <tool-name> <direct-note>
  if has "$2"; then echo "  $1: mcp:$2"; else echo "  $1: direct ($3)"; fi
}
echo "== capability map"
cap "list collections"   list-collections     "solr-api.sh … admin/collections?action=LIST"
cap "collection health"  check-health         "solr-api.sh … <coll>/admin/ping"
cap "cluster status"     get-cluster-status   "scripts/cluster-status.sh"
cap "list configsets"    list-configsets      "solr-api.sh … admin/configs?action=LIST"
cap "schema read"        get-schema           "solr-api.sh … <coll>/schema"
cap "schema add fields"  add-fields           "solr-api.sh … POST <coll>/schema"
cap "search"             search               "solr-api.sh … <coll>/select"
cap "index json"         index-json-documents "solr-api.sh … POST <coll>/update"
cap "aliases"            create-alias         "solr-api.sh … admin/collections?action=CREATEALIAS"
cap "backup"             backup-collection    "solr-api.sh … admin/collections?action=BACKUP"
cap "restore"            restore-collection   "solr-api.sh … admin/collections?action=RESTORE"
echo "  scale / upgrade / restart / storage / TLS / auth: kubectl on SolrCloud/$NAME (always)"
