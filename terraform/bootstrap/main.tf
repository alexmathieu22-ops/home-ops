# Secret zero: the one Kubernetes Secret that isn't managed by External Secrets Operator,
# because it's what ESO itself needs to bootstrap its 1Password SDK provider connection.
# Everything downstream of this flows through ExternalSecret -> 1Password. See
# docs/runbooks/secret-zero.md. Run once per cluster lifetime (and again only on token
# rotation) from an authenticated local `op` session — never committed, never SOPS-encrypted.

resource "kubernetes_namespace" "external_secrets" {
  metadata {
    name = "external-secrets"
  }
}

resource "kubernetes_secret" "onepassword_token" {
  metadata {
    name      = "onepassword-service-account-token"
    namespace = kubernetes_namespace.external_secrets.metadata[0].name
  }

  data = {
    token = var.onepassword_service_account_token
  }

  type = "Opaque"
}
