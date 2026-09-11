#!/usr/bin/env bash
# mcp-values-from-cr.sh — emit Helm values (or env) for solr-mcp derived from
# a SolrCloud CR. Prints the command to fetch the password; never the password.
# Usage: mcp-values-from-cr.sh <solrcloud-name> <namespace> [username=admin]
set -euo pipefail
NAME="${1:?usage: mcp-values-from-cr.sh <solrcloud> <namespace> [username]}"; NS="${2:?namespace}"; USER_="${3:-admin}"
CR=$(kubectl get solrcloud "$NAME" -n "$NS" -o json)
j() { echo "$CR" | jq -r "$1"; }
TLS=$(j 'if .spec.solrTLS then "true" else "false" end')
PORT=$(j '.spec.solrAddressability.commonServicePort // 80')
AUTH=$(j '.spec.solrSecurity.authenticationType // "none"')
USERSECRET=$(j '.spec.solrSecurity.basicAuthSecret // ""')
SCHEME=http; [ "$TLS" = "true" ] && SCHEME=https
SECRET="$NAME-solrcloud-security-bootstrap"; KEY="$USER_"
if [ -n "$USERSECRET" ]; then SECRET="$USERSECRET"; KEY="password"; fi
cat <<YAML
# Generated from SolrCloud/$NAME in $NS on $(date -u +%FT%TZ)
solrCloud:
  name: $NAME
  namespace: $NS
  commonServicePort: $PORT
  tls:
    enabled: $TLS
  auth:
    enabled: $([ "$AUTH" = "Basic" ] && echo true || echo false)
    secretName: $SECRET
    usernameKey: $KEY
# Equivalent environment for a plain Deployment:
#   SOLR_URL=$SCHEME://$NAME-solrcloud-common.$NS:$PORT/solr/
#   SOLR_USERNAME=$USER_
#   SOLR_PASSWORD=<from secret $SECRET key $KEY>
# To view the password yourself (do not paste it into chat):
#   kubectl get secret $SECRET -n $NS -o jsonpath='{.data.$KEY}' | base64 -d
YAML
[ "$TLS" = "true" ] && echo "# TLS is on: mount the CA that signed the Solr cert and set SOLR_TLS_CA_PEM (solr-mcp issue #2)." >&2
exit 0
