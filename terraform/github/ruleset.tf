# Requires org ownership (or GitHub Enterprise Cloud for private repos) -- the actual
# reason this repo moved from a personal account to alexmathieu22-ops. Without it,
# GitHub rejects the merge_queue rule type outright (422 "Invalid rule 'merge_queue'"),
# regardless of public/private status, with no useful error detail. See
# docs/runbooks/renovate.md's Merge queue section for the automerge-serialization
# problem this solves.
resource "github_repository_ruleset" "main_merge_queue" {
  name        = "main-merge-queue"
  repository  = var.repository
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["refs/heads/main"]
      exclude = []
    }
  }

  rules {
    merge_queue {
      check_response_timeout_minutes    = 30
      grouping_strategy                 = "ALLGREEN"
      max_entries_to_build              = 5
      max_entries_to_merge              = 5
      merge_method                      = "SQUASH"
      min_entries_to_merge              = 1
      min_entries_to_merge_wait_minutes = 0
    }

    # Same two jobs as ci.yaml / classic branch protection (docs/runbooks/renovate.md) --
    # duplicated here because the merge queue needs its own required_status_checks rule
    # to know what to test each queued PR against.
    required_status_checks {
      strict_required_status_checks_policy = true

      required_check {
        context = "Validate Kubernetes manifests"
      }
      required_check {
        context = "Validate talhelper config"
      }
    }
  }
}
