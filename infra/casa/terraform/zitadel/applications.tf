resource "zitadel_application_v2" "oauth2_proxy" {
  project_id = zitadel_project_v2.homelab.id
  org_id     = zitadel_organization.homelab.id
  name       = "Oauth Proxy"

  oidc {
    grant_types                  = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
    response_types               = ["OIDC_RESPONSE_TYPE_CODE"]
    redirect_uris                = ["https://oauth.${local.domain}/oauth2/callback"]
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
    redirect_uris                = ["https://beszel.${local.domain}/api/oauth2-redirect"]
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
    redirect_uris                = ["https://glitchtip.${local.domain}/accounts/oidc/zitadel/login/callback/"]
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
    redirect_uris                = ["https://ha.${local.domain}/auth/oidc/callback"]
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
    redirect_uris                = ["https://immich.${local.domain}/auth/login", "https://immich.${local.domain}/user-settings", "https://immich.${local.domain}/api/oauth/mobile-redirect"]
    post_logout_redirect_uris    = ["https://immich.${local.domain}/auth/login"]
    back_channel_logout_uri      = "https://immich.${local.domain}/api/oauth/backchannel-logout"
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
    redirect_uris                = ["https://zot.${local.domain}/zot/auth/callback/oidc"]
    post_logout_redirect_uris    = ["https://zot.${local.domain}/"]
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

resource "zitadel_application_v2" "element" {
  project_id = zitadel_project_v2.homelab.id
  org_id     = zitadel_organization.homelab.id
  name       = "Element"

  oidc {
    grant_types                  = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
    response_types               = ["OIDC_RESPONSE_TYPE_CODE"]
    redirect_uris                = ["https://element.${local.domain}/_synapse/client/oidc/callback"]
    post_logout_redirect_uris    = ["https://element.${local.domain}/"]
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

resource "zitadel_application_v2" "mas" {
  project_id = zitadel_project_v2.homelab.id
  org_id     = zitadel_organization.homelab.id
  name       = "Matrix Authentication Service"

  oidc {
    grant_types                  = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
    response_types               = ["OIDC_RESPONSE_TYPE_CODE"]
    redirect_uris                = ["https://mas.${local.domain}/upstream/callback/01K9A2B3C4D5E6F7G8H9J0KMNP"]
    post_logout_redirect_uris    = ["https://mas.${local.domain}/"]
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
    redirect_uris                = ["https://forgejo.${local.domain}/user/oauth2/zitadel/callback"]
    post_logout_redirect_uris    = ["https://forgejo.${local.domain}/"]
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
