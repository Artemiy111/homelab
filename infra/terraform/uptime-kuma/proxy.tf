resource "uptimekuma_proxy" "proxy" {
  for_each = toset(["xray"])

  host     = local.server_ip
  port     = 8440
  protocol = "http"
  active   = true
  auth     = false
}
