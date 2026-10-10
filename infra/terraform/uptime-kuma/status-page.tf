locals {
  monitor_ids = merge(
    { for key, monitor in local.monitors : key => uptimekuma_monitor_http.monitor[key].id if monitor.kind == "http" },
    { for key, monitor in local.monitors : key => uptimekuma_monitor_http_keyword.monitor[key].id if monitor.kind == "keyword" },
    { for key, monitor in local.monitors : key => uptimekuma_monitor_http_json_query.monitor[key].id if monitor.kind == "json" },
    { for key, monitor in local.monitors : key => uptimekuma_monitor_dns.monitor[key].id if monitor.kind == "dns" },
    { for key, monitor in local.monitors : key => uptimekuma_monitor_tcp_port.monitor[key].id if monitor.kind == "tcp" },
  )
}

resource "uptimekuma_status_page" "homelab" {
  slug                    = "homelab"
  title                   = "Homelab Status"
  description             = "Доступность сервисов домашнего сервера."
  published               = true
  show_certificate_expiry = true
  show_tags               = false
  show_powered_by         = false

  public_group_list = [
    for group in local.groups : {
      name   = group.title
      weight = group.weight
      monitor_list = [
        for key, monitor in local.monitors : {
          id       = local.monitor_ids[key]
          send_url = true
        } if monitor.group == group.key
      ]
    }
  ]
}
