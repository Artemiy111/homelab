# Однократная миграция: политики лежали плоско в корневом модуле, пока
# подкаталог policies/ не был подключён явно. Без moved terraform сделал бы
# destroy + create всех политик, а в промежутке у VSO не было бы прав.
# После apply файл можно удалить.

moved {
  from = vault_policy.app_3x_ui
  to   = module.policies.vault_policy.app_3x_ui
}

moved {
  from = vault_policy.app_ats
  to   = module.policies.vault_policy.app_ats
}

moved {
  from = vault_policy.app_authentik
  to   = module.policies.vault_policy.app_authentik
}

moved {
  from = vault_policy.app_beszel
  to   = module.policies.vault_policy.app_beszel
}

moved {
  from = vault_policy.app_dawarich
  to   = module.policies.vault_policy.app_dawarich
}

moved {
  from = vault_policy.app_element
  to   = module.policies.vault_policy.app_element
}

moved {
  from = vault_policy.app_forgejo
  to   = module.policies.vault_policy.app_forgejo
}

moved {
  from = vault_policy.app_gatus
  to   = module.policies.vault_policy.app_gatus
}

moved {
  from = vault_policy.app_glitchtip
  to   = module.policies.vault_policy.app_glitchtip
}

moved {
  from = vault_policy.app_grafana
  to   = module.policies.vault_policy.app_grafana
}

moved {
  from = vault_policy.app_home_assistant
  to   = module.policies.vault_policy.app_home_assistant
}

moved {
  from = vault_policy.app_immich
  to   = module.policies.vault_policy.app_immich
}

moved {
  from = vault_policy.app_infisical
  to   = module.policies.vault_policy.app_infisical
}

moved {
  from = vault_policy.app_jellyfin
  to   = module.policies.vault_policy.app_jellyfin
}

moved {
  from = vault_policy.app_jitsi
  to   = module.policies.vault_policy.app_jitsi
}

moved {
  from = vault_policy.app_local_ai
  to   = module.policies.vault_policy.app_local_ai
}

moved {
  from = vault_policy.app_mailserver
  to   = module.policies.vault_policy.app_mailserver
}

moved {
  from = vault_policy.app_navidrome
  to   = module.policies.vault_policy.app_navidrome
}

moved {
  from = vault_policy.app_nextcloud
  to   = module.policies.vault_policy.app_nextcloud
}

moved {
  from = vault_policy.app_oauth2_proxy
  to   = module.policies.vault_policy.app_oauth2_proxy
}

moved {
  from = vault_policy.app_open_webui
  to   = module.policies.vault_policy.app_open_webui
}

moved {
  from = vault_policy.app_paperless
  to   = module.policies.vault_policy.app_paperless
}

moved {
  from = vault_policy.app_pdf
  to   = module.policies.vault_policy.app_pdf
}

moved {
  from = vault_policy.app_postgres
  to   = module.policies.vault_policy.app_postgres
}

moved {
  from = vault_policy.app_rustfs
  to   = module.policies.vault_policy.app_rustfs
}

moved {
  from = vault_policy.app_seafile
  to   = module.policies.vault_policy.app_seafile
}

moved {
  from = vault_policy.app_sure
  to   = module.policies.vault_policy.app_sure
}

moved {
  from = vault_policy.app_talk_hpb
  to   = module.policies.vault_policy.app_talk_hpb
}

moved {
  from = vault_policy.app_technitium
  to   = module.policies.vault_policy.app_technitium
}

moved {
  from = vault_policy.app_uptime_kuma
  to   = module.policies.vault_policy.app_uptime_kuma
}

moved {
  from = vault_policy.app_vmagent
  to   = module.policies.vault_policy.app_vmagent
}
