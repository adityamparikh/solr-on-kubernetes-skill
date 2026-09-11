# Naming conventions the Solr Operator uses

Verified against `api/v1beta1/solrcloud_types.go` and `controllers/util/solr_util.go` on `apache/solr-operator` `main`. `<name>` is the `SolrCloud` name.

| Resource | Name | Notes |
|---|---|---|
| StatefulSet | `<name>-solrcloud` | |
| Pods | `<name>-solrcloud-0`, `-1`, … | Solr container is named `solrcloud-node` |
| Common Service | `<name>-solrcloud-common` | load-balances across ready pods; port `spec.solrAddressability.commonServicePort` (documented default 80) → pod port `spec.solrAddressability.podPort` (documented default 8983) |
| Headless Service | `<name>-solrcloud-headless` | per-pod DNS |
| ConfigMap | `<name>-solrcloud-configmap` | `solr.xml` |
| Bootstrap security Secret | `<name>-solrcloud-security-bootstrap` | keys `admin`, `solr`, `k8s-oper`; **values are passwords**; exists only when the operator bootstraps `security.json` |
| Basic-auth Secret | `<name>-solrcloud-basic-auth` | `kubernetes.io/basic-auth`, keys `username`/`password`, user `k8s-oper` — **the operator's probe identity; never use it** |
| Provided ZooKeeper | `<name>-solrcloud-zookeeper` | client service `<name>-solrcloud-zookeeper-client:2181` |

In-cluster Solr URL: `http(s)://<name>-solrcloud-common.<namespace>:<commonServicePort>/solr/`. Prefer reading `status.internalCommonAddress` over constructing it.

Default users when the operator bootstraps security (from the documented default `security.json`):
- `admin` — roles `admin`, `k8s`: everything
- `solr` — roles `users`, `k8s`: `read` plus `collection-admin-edit`; **cannot index or edit schema**
- `k8s-oper` — role `k8s`: probe endpoints and cluster status only

A solr-mcp deployment therefore needs `admin`, or a purpose-made user (see `assets/solr-mcp-user.json`).
