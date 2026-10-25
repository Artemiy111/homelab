resource "yandex_iam_service_account" "state" {
  name        = "terraform-state"
  description = "Чтение и запись state terraform-модулей yc в Object Storage"
}

resource "yandex_iam_service_account_static_access_key" "state" {
  service_account_id = yandex_iam_service_account.state.id
  description        = "S3 backend terraform"
}
