resource "zitadel_application_v2" "oauth2_proxy" {
  project_id = zitadel_project_v2.homelab.id
  org_id     = zitadel_organization.homelab.id
  name       = "Oauth Proxy"

  oidc {
    grant_types                  = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
    response_types               = ["OIDC_RESPONSE_TYPE_CODE"]
    redirect_uris                = ["https://oauth.${var.domain}/oauth2/callback"]
    app_type                     = "OIDC_APP_TYPE_WEB"
    auth_method_type             = "OIDC_AUTH_METHOD_TYPE_BASIC"
    version                      = "OIDC_VERSION_1_0"
    access_token_type            = "OIDC_TOKEN_TYPE_BEARER"
    clock_skew                   = "0s"
    skip_native_app_success_page = false
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "zitadel_application_v2" "beszel" {
  project_id = zitadel_project_v2.homelab.id
  org_id     = zitadel_organization.homelab.id
  name       = "Beszel"

  oidc {
    grant_types                  = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
    response_types               = ["OIDC_RESPONSE_TYPE_CODE"]
    redirect_uris                = ["https://beszel.${var.domain}/api/oauth2-redirect"]
    app_type                     = "OIDC_APP_TYPE_WEB"
    auth_method_type             = "OIDC_AUTH_METHOD_TYPE_BASIC"
    version                      = "OIDC_VERSION_1_0"
    access_token_type            = "OIDC_TOKEN_TYPE_BEARER"
    clock_skew                   = "0s"
    skip_native_app_success_page = false
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "zitadel_application_v2" "glitchtip" {
  project_id = zitadel_project_v2.homelab.id
  org_id     = zitadel_organization.homelab.id
  name       = "GlitchTip"

  oidc {
    grant_types                  = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
    response_types               = ["OIDC_RESPONSE_TYPE_CODE"]
    redirect_uris                = ["https://glitchtip.${var.domain}/accounts/oidc/zitadel/login/callback/"]
    app_type                     = "OIDC_APP_TYPE_WEB"
    auth_method_type             = "OIDC_AUTH_METHOD_TYPE_BASIC"
    version                      = "OIDC_VERSION_1_0"
    access_token_type            = "OIDC_TOKEN_TYPE_BEARER"
    clock_skew                   = "0s"
    skip_native_app_success_page = false
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "zitadel_application_v2" "home_assistant" {
  project_id = zitadel_project_v2.homelab.id
  org_id     = zitadel_organization.homelab.id
  name       = "Home Assistant"

  oidc {
    grant_types                  = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
    response_types               = ["OIDC_RESPONSE_TYPE_CODE"]
    redirect_uris                = ["https://ha.${var.domain}/auth/oidc/callback"]
    app_type                     = "OIDC_APP_TYPE_WEB"
    auth_method_type             = "OIDC_AUTH_METHOD_TYPE_BASIC"
    version                      = "OIDC_VERSION_1_0"
    access_token_type            = "OIDC_TOKEN_TYPE_BEARER"
    clock_skew                   = "0s"
    skip_native_app_success_page = false

    login_version {
      login_v2 {}
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "zitadel_application_v2" "seafile" {
  project_id = zitadel_project_v2.homelab.id
  org_id     = zitadel_organization.homelab.id
  name       = "Seafile"

  oidc {
    grant_types                  = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
    response_types               = ["OIDC_RESPONSE_TYPE_CODE"]
    redirect_uris                = ["https://seafile.${var.domain}/oauth/callback/"]
    app_type                     = "OIDC_APP_TYPE_WEB"
    auth_method_type             = "OIDC_AUTH_METHOD_TYPE_BASIC"
    version                      = "OIDC_VERSION_1_0"
    access_token_type            = "OIDC_TOKEN_TYPE_BEARER"
    clock_skew                   = "0s"
    skip_native_app_success_page = false
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "zitadel_application_v2" "immich" {
  project_id = zitadel_project_v2.homelab.id
  org_id     = zitadel_organization.homelab.id
  name       = "Immich"

  oidc {
    grant_types                  = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
    response_types               = ["OIDC_RESPONSE_TYPE_CODE"]
    redirect_uris                = ["https://immich.${var.domain}/auth/login", "https://immich.${var.domain}/user-settings", "https://immich.${var.domain}/api/oauth/mobile-redirect"]
    post_logout_redirect_uris    = ["https://immich.${var.domain}/auth/login"]
    back_channel_logout_uri      = "https://immich.${var.domain}/api/oauth/backchannel-logout"
    app_type                     = "OIDC_APP_TYPE_WEB"
    auth_method_type             = "OIDC_AUTH_METHOD_TYPE_NONE"
    version                      = "OIDC_VERSION_1_0"
    access_token_type            = "OIDC_TOKEN_TYPE_BEARER"
    clock_skew                   = "0s"
    skip_native_app_success_page = false
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "zitadel_application_v2" "zot" {
  project_id = zitadel_project_v2.homelab.id
  org_id     = zitadel_organization.homelab.id
  name       = "Zot"

  oidc {
    grant_types                  = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
    response_types               = ["OIDC_RESPONSE_TYPE_CODE"]
    redirect_uris                = ["https://zot.${var.domain}/zot/auth/callback/oidc"]
    post_logout_redirect_uris    = ["https://zot.${var.domain}/"]
    app_type                     = "OIDC_APP_TYPE_WEB"
    auth_method_type             = "OIDC_AUTH_METHOD_TYPE_BASIC"
    version                      = "OIDC_VERSION_1_0"
    access_token_type            = "OIDC_TOKEN_TYPE_BEARER"
    clock_skew                   = "0s"
    skip_native_app_success_page = false
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "zitadel_application_v2" "test" {
  project_id = zitadel_project_v2.homelab.id
  org_id     = zitadel_organization.homelab.id
  name       = "test"

  oidc {
    grant_types                  = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
    response_types               = ["OIDC_RESPONSE_TYPE_CODE"]
    redirect_uris                = ["http://127.0.0.1:8899/callback"]
    app_type                     = "OIDC_APP_TYPE_WEB"
    auth_method_type             = "OIDC_AUTH_METHOD_TYPE_BASIC"
    version                      = "OIDC_VERSION_1_0"
    access_token_type            = "OIDC_TOKEN_TYPE_BEARER"
    clock_skew                   = "0s"
    skip_native_app_success_page = false
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "zitadel_application_v2" "headlamp" {
  project_id = zitadel_project_v2.homelab.id
  org_id     = zitadel_organization.homelab.id
  name       = "Headlamp"

  oidc {
    grant_types       = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
    response_types    = ["OIDC_RESPONSE_TYPE_CODE"]
    redirect_uris     = ["https://headlamp.${var.domain}/oidc-callback"]
    app_type          = "OIDC_APP_TYPE_WEB"
    auth_method_type  = "OIDC_AUTH_METHOD_TYPE_BASIC"
    version           = "OIDC_VERSION_1_0"
    access_token_type = "OIDC_TOKEN_TYPE_BEARER"
    clock_skew        = "0s"
    # Claim `role` кладёт zitadel_trigger_actions.add_role_userinfo.
    # Headlamp шлёт id_token прямо в apiserver, поэтому claim должен быть в
    # самом токене, а не только в ответе userinfo.
    id_token_userinfo_assertion  = true
    skip_native_app_success_page = false
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Radar — свой OIDC-клиент, отдельный от Headlamp. Апстрим прямо советует не
# переиспользовать клиент, которому доверяет apiserver: сессия Radar хранит
# id_token пользователя, и утечка сессии дала бы токен и в apiserver.
#
# Claim `role` обязателен в самом id_token (id_token_userinfo_assertion): Radar
# читает группы из токена, а не из userinfo. С groupsPrefix `oidc:` группа
# получается ровно `oidc:admin` — та же, что у Headlamp, поэтому
# ClusterRoleBinding из platform/headlamp/ работает на оба UI.
resource "zitadel_application_v2" "radar" {
  project_id = zitadel_project_v2.homelab.id
  org_id     = zitadel_organization.homelab.id
  name       = "Radar"

  oidc {
    grant_types    = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
    response_types = ["OIDC_RESPONSE_TYPE_CODE"]
    redirect_uris  = ["https://radar.${var.domain}/auth/callback"]
    # Работает только если oauth2-proxy убран из маршрута Radar: Zitadel шлёт
    # сюда POST без cookie прокси, и forward-auth отдал бы 401.
    back_channel_logout_uri      = "https://radar.${var.domain}/auth/backchannel-logout"
    post_logout_redirect_uris    = ["https://radar.${var.domain}/"]
    app_type                     = "OIDC_APP_TYPE_WEB"
    auth_method_type             = "OIDC_AUTH_METHOD_TYPE_BASIC"
    version                      = "OIDC_VERSION_1_0"
    access_token_type            = "OIDC_TOKEN_TYPE_BEARER"
    clock_skew                   = "0s"
    id_token_userinfo_assertion  = true
    skip_native_app_success_page = false
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "zitadel_application_v2" "element" {
  project_id = zitadel_project_v2.homelab.id
  org_id     = zitadel_organization.homelab.id
  name       = "Element"

  oidc {
    grant_types                  = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
    response_types               = ["OIDC_RESPONSE_TYPE_CODE"]
    redirect_uris                = ["https://element.${var.domain}/_synapse/client/oidc/callback"]
    post_logout_redirect_uris    = ["https://element.${var.domain}/"]
    app_type                     = "OIDC_APP_TYPE_WEB"
    auth_method_type             = "OIDC_AUTH_METHOD_TYPE_BASIC"
    version                      = "OIDC_VERSION_1_0"
    access_token_type            = "OIDC_TOKEN_TYPE_BEARER"
    clock_skew                   = "0s"
    id_token_userinfo_assertion  = true
    skip_native_app_success_page = false
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Имя сегмента `zitadel` в пути колбэка не декоративно: Forgejo ищет источник
# по имени (`GetActiveOAuth2SourceByName`), а не по id, и подставляет это же
# имя в URL кнопки входа. Имя источника в values чарта и redirect URI здесь
# обязаны совпадать.
resource "zitadel_application_v2" "forgejo" {
  project_id = zitadel_project_v2.homelab.id
  org_id     = zitadel_organization.homelab.id
  name       = "Forgejo"

  oidc {
    grant_types                  = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
    response_types               = ["OIDC_RESPONSE_TYPE_CODE"]
    redirect_uris                = ["https://forgejo.${var.domain}/user/oauth2/zitadel/callback"]
    post_logout_redirect_uris    = ["https://forgejo.${var.domain}/"]
    app_type                     = "OIDC_APP_TYPE_WEB"
    auth_method_type             = "OIDC_AUTH_METHOD_TYPE_BASIC"
    version                      = "OIDC_VERSION_1_0"
    access_token_type            = "OIDC_TOKEN_TYPE_BEARER"
    clock_skew                   = "0s"
    skip_native_app_success_page = false
  }

  lifecycle {
    prevent_destroy = true
  }
}
