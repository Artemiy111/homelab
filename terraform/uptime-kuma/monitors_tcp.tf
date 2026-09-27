resource "uptimekuma_monitor_tcp_port" "monitor" {
  for_each = { for key, monitor in local.monitors : key => monitor if monitor.kind == "tcp" }

  name            = each.value.name
  description     = each.value.description
  hostname        = each.value.hostname
  port            = each.value.port
  active          = each.value.active
  interval        = each.value.interval
  retry_interval  = each.value.retry_interval
  resend_interval = each.value.resend_interval
  max_retries     = each.value.max_retries
  upside_down     = each.value.upside_down

  tags = [
    { tag_id = uptimekuma_tag.group[each.value.group].id },
  ]
}
