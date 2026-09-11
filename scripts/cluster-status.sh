#!/usr/bin/env bash
# cluster-status.sh — direct-mode equivalent of solr-mcp's get-cluster-status.
#
# Usage: cluster-status.sh <solrcloud-name> <namespace> [collection]
#
# Calls CLUSTERSTATUS through solr-api.sh and reduces it to:
#   { healthy, issues[], liveNodes[], collections{ <name>: { replicationFactor, shards{ <shard>: { leader, replicas[] } } } } }
# issues[] lists every replica whose state is not "active" or whose node is
# not live. Read `healthy` and `issues` first; `collections` is detail.
set -euo pipefail
NAME="${1:?usage: cluster-status.sh <solrcloud> <namespace> [collection]}"
NS="${2:?namespace}"
COLL="${3:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
Q='admin/collections?action=CLUSTERSTATUS&wt=json'
[ -n "$COLL" ] && Q="$Q&collection=$COLL"
RESPONSE=$("$HERE/solr-api.sh" "$NAME" "$NS" GET "$Q")
printf '%s\n' "$RESPONSE" | jq -e '
  if type != "object" then error("Invalid CLUSTERSTATUS response")
  elif .responseHeader.status != 0 or .error != null then error("CLUSTERSTATUS failed")
  elif (.cluster | type) != "object"
    or (.cluster.live_nodes | type) != "array"
    or (.cluster.collections | type) != "object"
  then error("Invalid CLUSTERSTATUS cluster structure")
  else . end
  | .cluster as $c
  | $c.live_nodes as $live
  | $c.collections as $cols
  | {
      liveNodes: $live,
      collections: ($cols | with_entries(.value |= {
          replicationFactor: (.replicationFactor // null),
          shards: ((.shards // {}) | with_entries(.value |= {
              leader: ((.replicas // {}) | to_entries | map(select(.value.leader == "true")) | .[0].key),
              replicas: ((.replicas // {}) | to_entries | map({name: .key, node: .value.node_name, state: .value.state}))
          }))
      })),
      issues: [ $cols | to_entries[] as $col
                | ($col.value.shards // {}) | to_entries[] as $sh
                | ($sh.value.replicas // {}) | to_entries[] as $r
                | select($r.value.state != "active" or (($live | index($r.value.node_name)) == null))
                | {collection: $col.key, shard: $sh.key, replica: $r.key, node: $r.value.node_name,
                   state: (if ($live | index($r.value.node_name)) == null then "node_down" else $r.value.state end)} ]
    }
  | .healthy = (.issues | length == 0)
  | {healthy, issues, liveNodes, collections}'
