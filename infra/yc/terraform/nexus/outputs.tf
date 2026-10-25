output "cluster_id" {
  description = "Идентификатор кластера Managed Service for PostgreSQL"
  value       = yandex_mdb_postgresql_cluster.nexus.id
}

output "hosts" {
  description = "FQDN хостов PostgreSQL; Nexus подключается к обоим через targetServerType=primary"
  value       = [for host in yandex_mdb_postgresql_cluster.nexus.host : host.fqdn]
}

output "port" {
  description = "Порт подключения к PostgreSQL"
  value       = local.port
}

output "database" {
  description = "Имя базы"
  value       = yandex_mdb_postgresql_database.nexus.name
}

output "user" {
  description = "Имя роли"
  value       = yandex_mdb_postgresql_user.nexus.name
}

output "connection_id" {
  description = "Подключение Connection Manager"
  value       = data.yandex_connectionmanager_connection.nexus.id
}

output "lockbox_secret_id" {
  description = "Секрет Lockbox с паролем роли"
  value       = data.yandex_connectionmanager_connection.nexus.lockbox_secret.id
}

output "lockbox_secret_entry" {
  description = "Ключ записи в секрете Lockbox"
  value       = "postgresql_password"
}

output "lockbox_service_account" {
  description = "Сервисный аккаунт, которому разрешено читать секрет"
  value       = yandex_iam_service_account.lockbox.name
}

output "lockbox_service_account_id" {
  description = "Идентификатор сервисного аккаунта для создания авторизованного ключа"
  value       = yandex_iam_service_account.lockbox.id
}
