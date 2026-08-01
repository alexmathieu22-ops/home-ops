variable "kubeconfig_path" {
  description = "Path to the kubeconfig used to reach the cluster (local dev cluster or real hardware)."
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "kubeconfig context to use. Null uses the current context."
  type        = string
  default     = null
}

variable "onepassword_service_account_token" {
  description = <<-EOT
    1Password Service Account token, scoped to the infra vault. This is "secret zero" —
    it is never committed to Git and never SOPS-encrypted; it's read once from an
    authenticated local `op` session and passed in via TF_VAR_onepassword_service_account_token.
    See docs/runbooks/secret-zero.md.
  EOT
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition     = length(var.onepassword_service_account_token) > 0
    error_message = "onepassword_service_account_token is empty. The 1Password account/vault/Service Account haven't been created yet (deferred per PROJECT_BRIEF.md). Once they exist: export TF_VAR_onepassword_service_account_token=$(op read \"op://<vault>/<item>/token\") from an authenticated `op` session, then re-run `tofu apply`."
  }
}
