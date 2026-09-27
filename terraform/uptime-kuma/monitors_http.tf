resource "uptimekuma_monitor_http" "monitor" {
  for_each = { for key, monitor in local.monitors : key => monitor if monitor.kind == "http" }

  name                  = each.value.name
  description           = each.value.description
  url                   = each.value.url
  active                = each.value.active
  interval              = each.value.interval
  retry_interval        = each.value.retry_interval
  resend_interval       = each.value.resend_interval
  timeout               = each.value.timeout
  max_retries           = each.value.max_retries
  max_redirects         = each.value.max_redirects
  accepted_status_codes = each.value.accepted_status_codes
  method                = "GET"
  ignore_tls            = each.value.ignore_tls
  upside_down           = each.value.upside_down
  proxy_id              = each.value.proxy_key == null ? null : uptimekuma_proxy.proxy[each.value.proxy_key].id

  tags = [
    { tag_id = uptimekuma_tag.group[each.value.group].id },
  ]
}
