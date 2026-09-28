resource "zitadel_project_v2" "homelab" {
  name   = "Homelab"
  org_id = zitadel_organization.homelab.id

  project_role_assertion = true
  project_role_check     = false
  has_project_check      = false

  lifecycle {
    prevent_destroy = true
  }
}
