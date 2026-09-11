#!/usr/bin/env bash
# wait-ready.sh — block until SolrCloud.status.readyReplicas == spec.replicas
# and status.upToDateNodes == spec.replicas (no rollout in progress).
# Usage: wait-ready.sh <solrcloud-name> <namespace> [timeout-seconds=600]
set -euo pipefail
NAME="${1:?usage: wait-ready.sh <solrcloud> <namespace> [timeout]}"; NS="${2:?namespace}"; T="${3:-600}"
end=$(( $(date +%s) + T ))
while :; do
  read -r want ready upd < <(kubectl get solrcloud "$NAME" -n "$NS" -o jsonpath='{.spec.replicas} {.status.readyReplicas} {.status.upToDateNodes}' 2>/dev/null | awk '{print ($1==""?"?":$1), ($2==""?0:$2), ($3==""?0:$3)}')
  echo "$(date +%T) ready=$ready/$want upToDate=$upd/$want"
  if [ "$ready" = "$want" ] && [ "$upd" = "$want" ]; then echo "ready"; exit 0; fi
  [ "$(date +%s)" -ge "$end" ] && { echo "timeout after ${T}s" >&2; exit 1; }
  sleep 10
done
