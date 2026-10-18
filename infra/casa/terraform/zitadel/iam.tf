locals {
  users = {
    instance_admin  = "387300440830181379"
    homelab_admin   = "387308085636497411"
    homelab_service = "387704510765596693"
    test            = "388550157697810435"
  }
}

resource "zitadel_instance_member" "instance_admin" {
  user_id = local.users.instance_admin
  roles   = ["IAM_OWNER"]

  lifecycle {
    prevent_destroy = true
  }
}

resource "zitadel_org_member" "instance_admin" {
  org_id  = zitadel_organization.homelab.id
  user_id = local.users.instance_admin
  roles   = ["ORG_OWNER"]

  lifecycle {
    prevent_destroy = true
  }
}

resource "zitadel_org_member" "homelab_admin" {
  org_id  = zitadel_organization.homelab.id
  user_id = local.users.homelab_admin
  roles   = ["ORG_OWNER"]

  lifecycle {
    prevent_destroy = true
  }
}

resource "zitadel_org_member" "homelab_service" {
  org_id  = zitadel_organization.homelab.id
  user_id = local.users.homelab_service
  roles   = ["ORG_OWNER"]

  lifecycle {
    prevent_destroy = true
  }
}

resource "zitadel_project_role" "admin" {
  project_id   = zitadel_project_v2.homelab.id
  org_id       = zitadel_organization.homelab.id
  role_key     = "admin"
  display_name = "Application Admin"
  group        = "default"

  lifecycle {
    prevent_destroy = true
  }
}

resource "zitadel_project_role" "wtf" {
  project_id   = zitadel_project_v2.homelab.id
  org_id       = zitadel_organization.homelab.id
  role_key     = "wtf"
  display_name = "Wthat tf"
  group        = "test-group"

  lifecycle {
    prevent_destroy = true
  }
}

resource "zitadel_user_grant" "homelab_admin" {
  org_id     = zitadel_organization.homelab.id
  user_id    = local.users.homelab_admin
  project_id = zitadel_project_v2.homelab.id
  role_keys  = ["admin"]

  lifecycle {
    prevent_destroy = true
  }
}

resource "zitadel_user_grant" "test" {
  org_id     = zitadel_organization.homelab.id
  user_id    = local.users.test
  project_id = zitadel_project_v2.homelab.id
  role_keys  = ["admin"]

  lifecycle {
    prevent_destroy = true
  }
}
