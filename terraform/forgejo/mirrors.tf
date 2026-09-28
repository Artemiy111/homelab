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

  description = each.value.description
  private     = false

  clone_addr      = each.value.clone_addr
  mirror          = true
  mirror_interval = each.value.mirror_interval

  has_actions       = false
  has_issues        = false
  has_packages      = false
  has_projects      = false
  has_pull_requests = false
  has_releases      = false
  has_wiki          = false

  lifecycle {
    prevent_destroy = true

    ignore_changes = [
      allow_merge_commits,
      allow_rebase,
      allow_rebase_explicit,
      allow_squash_merge,
      default_merge_style,
      ignore_whitespace_conflicts,
    ]
  }
}
