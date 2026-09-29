# Claim `role` в id_token. На обоих триггерах один и тот же action: при входе
# в Zitadel (для Immich) и при выдаче токена (для Headlamp).
resource "zitadel_action" "add_role" {
  org_id  = zitadel_organization.homelab.id
  name    = "addRole"
  timeout = "1s"

  script          = <<-EOT
function addRole(ctx, api) {
  let grants = ctx.v1.user.grants;
  if (!grants || grants.count === 0) return;
  let isAdmin = false;
  for (const g of grants.grants) {
    if (g.roles.includes('admin')) {   // ← имя роли
      isAdmin = true;
      break;
    }
  }

  api.v1.claims.setClaim('role', isAdmin ? 'admin' : 'user');
}
  EOT
  allowed_to_fail = true

  lifecycle {
    prevent_destroy = true
  }
}

# Триггер на момент входа в Zitadel: claim попадает в профиль пользователя.
# Нужен приложениям, читающим роль из userinfo.
resource "zitadel_trigger_actions" "add_role_internal_auth" {
  org_id       = zitadel_organization.homelab.id
  flow_type    = "FLOW_TYPE_INTERNAL_AUTHENTICATION"
  trigger_type = "TRIGGER_TYPE_POST_AUTHENTICATION"
  action_ids   = [zitadel_action.add_role.id]
}

# Триггер перед выпуском токена: claim попадает внутрь id_token, который
# Headlamp отдаёт apiserver'у. apiserver читает его как группу и выдаёт
# cluster-admin только роли `admin`.
resource "zitadel_trigger_actions" "add_role_customise_token" {
  org_id       = zitadel_organization.homelab.id
  flow_type    = "FLOW_TYPE_CUSTOMISE_TOKEN"
  trigger_type = "TRIGGER_TYPE_PRE_USERINFO_CREATION"
  action_ids   = [zitadel_action.add_role.id]
}
