resource "zitadel_organization" "homelab" {
  name = "homelab"

  lifecycle {
    prevent_destroy = true
  }
}

resource "zitadel_organization_domain" "homelab" {
  organization_id = zitadel_organization.homelab.id
  domain          = "homelab.id.${var.domain}"

  lifecycle {
    prevent_destroy = true
  }
}
