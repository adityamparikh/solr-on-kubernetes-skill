#!/usr/bin/env bash
# solr-api.sh — call the Solr HTTP API of an operator-managed SolrCloud
# without solr-mcp, by running curl inside one of the Solr pods.
#
# Usage: solr-api.sh <solrcloud-name> <namespace> <METHOD> <path> [extra curl args...]
#
#   solr-api.sh films search GET  'admin/collections?action=LIST'
#   solr-api.sh films search GET  'films/select?q=*:*&rows=0'
#   solr-api.sh films search POST 'films/schema' --data-binary @add-field.json
#
# <path> is relative to /solr/ (no leading slash). Extra args go to curl
# unchanged, so --data-binary, -H etc. work. @file args must be readable
# from the workstation; the script streams them into the pod.
#
# Credentials: SOLR_USER (default: admin) is looked up in the operator's
# bootstrap secret <name>-solrcloud-security-bootstrap, or in SOLR_AUTH_SECRET
# (a kubernetes.io/basic-auth secret with username/password keys) when set.
# The password is read by kubectl and written to curl's stdin inside the pod
# via a --config file; it never appears as an argument on either side.
#
# Why in-pod: the pod already has network access, no port-forward is needed,
# NetworkPolicies are respected, and TLS to localhost inside the pod does not
# need the CA on the workstation.
set -euo pipefail

NAME="${1:?usage: solr-api.sh <solrcloud> <namespace> <METHOD> <path> [curl args]}"
NS="${2:?namespace}"
METHOD="${3:?METHOD}"
APIPATH="${4:?path}"
shift 4

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing dependency: $1" >&2; exit 2; }; }
need kubectl; need jq

CR=$(kubectl get solrcloud "$NAME" -n "$NS" -o json)
AUTH=$(echo "$CR" | jq -r '.spec.solrSecurity.authenticationType // "none"')
TLS=$(echo "$CR" | jq -r 'if .spec.solrTLS then "yes" else "no" end')
PODPORT=$(echo "$CR" | jq -r '.spec.solrAddressability.podPort // 8983')
POD="$NAME-solrcloud-0"
SCHEME=http; INSECURE=""
if [ "$TLS" = "yes" ]; then SCHEME=https; INSECURE="insecure"; fi   # loopback inside the pod

USER_="${SOLR_USER:-admin}"
PASS=""
if [ "$AUTH" = "Basic" ]; then
  if [ -n "${SOLR_AUTH_SECRET:-}" ]; then
    USER_=$(kubectl get secret "$SOLR_AUTH_SECRET" -n "$NS" -o jsonpath='{.data.username}' | base64 -d)
    PASS=$(kubectl get secret "$SOLR_AUTH_SECRET" -n "$NS" -o jsonpath='{.data.password}' | base64 -d)
  else
    # Bootstrap secret is keyed by username; value is the password.
    PASS=$(kubectl get secret "$NAME-solrcloud-security-bootstrap" -n "$NS" -o jsonpath="{.data.$USER_}" | base64 -d) \
      || { echo "no password for user '$USER_' in $NAME-solrcloud-security-bootstrap" >&2; exit 3; }
    if [ -z "$PASS" ]; then echo "user '$USER_' not in bootstrap secret; set SOLR_AUTH_SECRET" >&2; exit 3; fi
  fi
fi

URL="$SCHEME://localhost:$PODPORT/solr/$APIPATH"

# Build a curl config on stdin so the credential is never an argv entry.
# Any @file arguments are inlined by kubectl exec's stdin only if we cat them;
# simplest robust approach: pass remaining args through, and let curl inside
# the pod read the config for auth + URL.
CFG=$(mktemp); trap 'rm -f "$CFG"' EXIT
{
  echo "url = \"$URL\""
  echo "request = \"$METHOD\""
  echo "silent"
  echo "show-error"
  [ -n "$INSECURE" ] && echo "$INSECURE"
  [ -n "$PASS" ] && printf 'user = "%s:%s"\n' "$USER_" "$PASS"
} > "$CFG"

# Extra args containing @file are rewritten to read from stdin is not possible
# for multiple files; support the common single --data-binary @file case by
# appending its content to the config as a data field.
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --data-binary|--data|-d)
      if [[ "${2:-}" == @* ]]; then
        f="${2#@}"
        # curl config: data-binary = "@-" reads stdin; we cannot use stdin twice,
        # so embed the file content directly. Escapes quotes and backslashes.
        esc=$(sed 's/\\/\\\\/g; s/"/\\"/g' "$f" | tr -d '\n')
        echo "header = \"Content-Type: application/json\"" >> "$CFG"
        echo "data-binary = \"$esc\"" >> "$CFG"
        shift 2; continue
      fi;;
  esac
  ARGS+=("$1"); shift
done

# Stream the config into the pod and run curl against it. -K - reads config from stdin.
kubectl exec -i "$POD" -n "$NS" -c solrcloud-node -- curl -K - "${ARGS[@]}" < "$CFG"
echo
