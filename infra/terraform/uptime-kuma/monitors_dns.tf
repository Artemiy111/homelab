resource "uptimekuma_monitor_dns" "monitor" {
  for_each = { for key, monitor in local.monitors : key => monitor if monitor.kind == "dns" }

  name               = each.value.name
  description        = each.value.description
  hostname           = each.value.hostname
  dns_resolve_server = each.value.dns_resolve_server
  dns_resolve_type   = each.value.dns_resolve_type
  port               = each.value.dns_port
  conditions         = each.value.conditions
  active             = each.value.active
  interval           = each.value.interval
  retry_interval     = each.value.retry_interval
  resend_interval    = each.value.resend_interval
  max_retries        = each.value.max_retries
  upside_down        = each.value.upside_down

  tags = [
    { tag_id = uptimekuma_tag.group[each.value.group].id },
  ]
}
