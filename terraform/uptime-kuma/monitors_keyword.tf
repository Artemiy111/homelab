resource "uptimekuma_monitor_http_keyword" "monitor" {
  for_each = { for key, monitor in local.monitors : key => monitor if monitor.kind == "keyword" }

  name                  = each.value.name
  description           = each.value.description
  url                   = each.value.url
  keyword               = each.value.keyword
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
  invert_keyword        = false
  upside_down           = each.value.upside_down

  tags = [
    { tag_id = uptimekuma_tag.group[each.value.group].id },
  ]
}
