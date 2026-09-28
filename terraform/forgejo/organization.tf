resource "forgejo_organization" "actions" {
  name = "actions"

  visibility                    = "public"
  repo_admin_change_team_access = true

  lifecycle {
    prevent_destroy = true
  }
}
