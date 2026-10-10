locals {
  mirrors = {
    cascading-pr      = "https://data.forgejo.org/actions/cascading-pr.git"
    checkout          = "https://data.forgejo.org/actions/checkout.git"
    download-artifact = "https://data.forgejo.org/actions/download-artifact.git"
    forgejo-release   = "https://data.forgejo.org/actions/forgejo-release.git"
    git-backporting   = "https://data.forgejo.org/actions/git-backporting.git"
    git-pages         = "https://data.forgejo.org/actions/git-pages.git"
    go-hashfiles      = "https://data.forgejo.org/actions/go-hashfiles.git"
    go-versions       = "https://data.forgejo.org/actions/go-versions.git"
    renovate-config   = "https://code.forgejo.org/actions/renovate-config.git"
    setup-forgejo     = "https://data.forgejo.org/actions/setup-forgejo.git"
    setup-go          = "https://data.forgejo.org/actions/setup-go.git"
    setup-java        = "https://data.forgejo.org/actions/setup-java.git"
    setup-node        = "https://data.forgejo.org/actions/setup-node.git"
    setup-python      = "https://data.forgejo.org/actions/setup-python.git"
    upload-artifact   = "https://data.forgejo.org/actions/upload-artifact.git"
  }

  mirror_interval = "8h0m0s"
}

resource "forgejo_repository" "mirror" {
  for_each = local.mirrors

  owner = "actions"
  name  = each.key

  description     = "Mirror of ${trimsuffix(trimprefix(each.value, "https://"), ".git")} for offline CI"
  private         = false
  clone_addr      = each.value
  mirror          = true
  mirror_interval = local.mirror_interval

  has_actions       = false
  has_issues        = false
  has_packages      = false
  has_projects      = false
  has_pull_requests = false
  has_releases      = true
  has_wiki          = false

  lifecycle {
    prevent_destroy = true
  }
}
