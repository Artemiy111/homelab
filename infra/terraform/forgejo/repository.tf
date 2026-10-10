resource "forgejo_repository" "homelab" {
  name  = "homelab"
  owner = "artemiy"

  private        = true
  default_branch = "main"
  archived       = false

  has_actions       = true
  has_issues        = true
  has_packages      = true
  has_projects      = true
  has_pull_requests = true
  has_releases      = true
  has_wiki          = true

  globally_editable_wiki      = false
  wiki_branch                 = "main"
  ignore_whitespace_conflicts = false

  allow_merge_commits           = false
  allow_rebase                  = false
  allow_rebase_explicit         = false
  allow_rebase_update           = true
  allow_squash_merge            = true
  allow_fast_forward_only_merge = false

  default_merge_style               = "squash"
  default_delete_branch_after_merge = true
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
