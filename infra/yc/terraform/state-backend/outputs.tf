output "bucket" {
  description = "Бакет с state"
  value       = yandex_storage_bucket.tfstate.bucket
}

output "access_key" {
  description = "Идентификатор статического ключа сервисного аккаунта terraform-state"
  value       = yandex_iam_service_account_static_access_key.state.access_key
  sensitive   = true
}

output "secret_key" {
  description = "Секрет статического ключа сервисного аккаунта terraform-state"
  value       = yandex_iam_service_account_static_access_key.state.secret_key
  sensitive   = true
}
