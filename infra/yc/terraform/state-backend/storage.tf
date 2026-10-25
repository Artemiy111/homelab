resource "yandex_storage_bucket" "tfstate" {
  bucket        = local.bucket_name
  force_destroy = false

  versioning {
    enabled = true
  }

  anonymous_access_flags {
    read = false
    list = false
  }
}

resource "yandex_storage_bucket_iam_binding" "state" {
  bucket  = yandex_storage_bucket.tfstate.bucket
  role    = "storage.editor"
  members = ["serviceAccount:${yandex_iam_service_account.state.id}"]
}
