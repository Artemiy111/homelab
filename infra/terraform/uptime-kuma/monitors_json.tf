resource "uptimekuma_monitor_http_json_query" "monitor" {
  for_each = { for key, monitor in local.monitors : key => monitor if monitor.kind == "json" }

  name                  = each.value.name
  description           = each.value.description
  url                   = each.value.url
  json_path             = each.value.json_path
  json_path_operator    = each.value.json_path_operator
  expected_value        = each.value.expected_value
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

  tags = [
    { tag_id = uptimekuma_tag.group[each.value.group].id },
  ]
}
