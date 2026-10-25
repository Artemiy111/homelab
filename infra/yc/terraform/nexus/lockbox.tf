data "yandex_connectionmanager_connection" "nexus" {
  connection_id = yandex_mdb_postgresql_user.nexus.user_connection_manager[0].connection_id
}

resource "yandex_iam_service_account" "lockbox" {
  name        = "nexus-lockbox"
  description = "Чтение пароля PostgreSQL Nexus из Lockbox"
}

resource "yandex_lockbox_secret_iam_member" "nexus" {
  secret_id = data.yandex_connectionmanager_connection.nexus.lockbox_secret.id
  role      = "lockbox.payloadViewer"
  member    = "serviceAccount:${yandex_iam_service_account.lockbox.id}"
}
