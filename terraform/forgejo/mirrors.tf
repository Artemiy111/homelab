locals {
  mirrors = {
    checkout = {
      description     = "Mirror of data.forgejo.org/actions/checkout for offline CI"
      clone_addr      = "https://data.forgejo.org/actions/checkout.git"
      mirror_interval = "8h0m0s"
    }
  }
}

resource "forgejo_repository" "mirror" {
  for_each = local.mirrors

  owner = "actions"
  name  = each.key

  description     = each.value.description
  private         = false
  default_branch  = "main"
  archived        = false
  clone_addr      = each.value.clone_addr
  mirror          = true
  mirror_interval = each.value.mirror_interval

  has_actions       = false
  has_issues        = true
  has_packages      = true
  has_projects      = true
  has_pull_requests = false
  has_releases      = true
  has_wiki          = true

  globally_editable_wiki      = false
  wiki_branch                 = "main"
  ignore_whitespace_conflicts = false

  allow_merge_commits           = false
  allow_rebase                  = false
  allow_rebase_explicit         = false
  allow_rebase_update           = false
  allow_squash_merge            = false
  allow_fast_forward_only_merge = false

  default_merge_style               = "merge"
  default_delete_branch_after_merge = false
  default_allow_maintainer_edit     = false
  default_update_style              = "merge"

  internal_tracker = {
    enable_time_tracker                   = true
    allow_only_contributors_to_track_time = true
    enable_issue_dependencies             = true
  }

  lifecycle {
    prevent_destroy = true
  }
}
