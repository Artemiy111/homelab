locals {
  mirrors = {
    cascading-pr = {
      owner    = "actions"
      upstream = "https://data.forgejo.org/actions/cascading-pr.git"
    }
    checkout = {
      owner    = "actions"
      upstream = "https://data.forgejo.org/actions/checkout.git"
    }
    download-artifact = {
      owner    = "actions"
      upstream = "https://data.forgejo.org/actions/download-artifact.git"
    }
    forgejo-release = {
      owner    = "actions"
      upstream = "https://data.forgejo.org/actions/forgejo-release.git"
    }
    git-backporting = {
      owner    = "actions"
      upstream = "https://data.forgejo.org/actions/git-backporting.git"
    }
    git-pages = {
      owner    = "actions"
      upstream = "https://data.forgejo.org/actions/git-pages.git"
    }
    go-hashfiles = {
      owner    = "actions"
      upstream = "https://data.forgejo.org/actions/go-hashfiles.git"
    }
    go-versions = {
      owner    = "actions"
      upstream = "https://data.forgejo.org/actions/go-versions.git"
    }
    renovate-config = {
      owner    = "actions"
      upstream = "https://code.forgejo.org/actions/renovate-config.git"
    }
    setup-bun = {
      owner    = "oven-sh"
      upstream = "https://github.com/oven-sh/setup-bun"
    }
    setup-forgejo = {
      owner    = "actions"
      upstream = "https://data.forgejo.org/actions/setup-forgejo.git"
    }
    setup-go = {
      owner    = "actions"
      upstream = "https://data.forgejo.org/actions/setup-go.git"
    }
    setup-java = {
      owner    = "actions"
      upstream = "https://data.forgejo.org/actions/setup-java.git"
    }
    setup-node = {
      owner    = "actions"
      upstream = "https://data.forgejo.org/actions/setup-node.git"
    }
    setup-python = {
      owner    = "actions"
      upstream = "https://data.forgejo.org/actions/setup-python.git"
    }
    setup-trivy = {
      owner    = forgejo_organization.aquasecurity.name
      upstream = "https://github.com/aquasecurity/setup-trivy"
    }
    trivy = {
      owner    = forgejo_organization.aquasecurity.name
      upstream = "https://github.com/aquasecurity/trivy"
    }
    trivy-action = {
      owner    = forgejo_organization.aquasecurity.name
      upstream = "https://github.com/aquasecurity/trivy-action"
    }
    upload-artifact = {
      owner    = "actions"
      upstream = "https://data.forgejo.org/actions/upload-artifact.git"
    }
  }

  mirror_interval = "8h0m0s"
}

resource "forgejo_organization" "aquasecurity" {
  name       = "aquasecurity"
  visibility = "public"

  lifecycle {
    prevent_destroy = true
  }
}

resource "forgejo_repository" "mirror" {
  for_each = local.mirrors

  owner = each.value.owner
  name  = each.key

  description     = "Mirror of ${trimsuffix(trimprefix(each.value.upstream, "https://"), ".git")} for offline CI"
  private         = false
  clone_addr      = each.value.upstream
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
