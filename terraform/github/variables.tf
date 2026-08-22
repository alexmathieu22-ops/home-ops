variable "github_owner" {
  description = "Organization that owns the repo -- see IMPLEMENTATION_NOTES.md for why this moved from a personal account."
  type        = string
  default     = "alexmathieu22-ops"
}

variable "github_token" {
  description = "GitHub token with Administration:write on the repo (fine-grained PAT) or classic `repo` scope -- `gh auth token` works for local runs. Needs repo-admin rights to manage rulesets."
  type        = string
  sensitive   = true
}

variable "repository" {
  description = "Repo name this module manages rulesets for"
  type        = string
  default     = "home-ops"
}
