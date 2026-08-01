output "external_secrets_namespace" {
  description = "Namespace holding the 1Password secret-zero Secret."
  value       = kubernetes_namespace.external_secrets.metadata[0].name
}

output "onepassword_secret_name" {
  description = "Name of the Secret ESO's ClusterSecretStore references for the 1Password SDK provider."
  value       = kubernetes_secret.onepassword_token.metadata[0].name
}
