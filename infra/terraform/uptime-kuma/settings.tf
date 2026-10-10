resource "uptimekuma_settings" "this" {
  server_timezone        = var.timezone
  primary_base_url       = "https://kuma.${var.domain}"
  tls_expiry_notify_days = [7]
  search_engine_index    = false
}
