data "uptimekuma_monitor_http" "technitium-http" {
  name = "Technitium HTTP"
}

data "uptimekuma_monitor_http" "traefik" {
  name = "Traefik"
}

data "uptimekuma_monitor_http" "jitsi-meet" {
  name = "Jitsi Meet"
}

data "uptimekuma_monitor_http" "mermaid" {
  name = "Mermaid Live Editor"
}

data "uptimekuma_monitor_http" "nextcloud" {
  name = "Nextcloud"
}

data "uptimekuma_monitor_http" "forgejo" {
  name = "Forgejo"
}

data "uptimekuma_monitor_http" "code-server" {
  name = "code-server"
}

data "uptimekuma_monitor_http" "authentik" {
  name = "Authentik"
}

data "uptimekuma_monitor_http" "localai" {
  name = "LocalAI"
}

data "uptimekuma_monitor_http" "immich" {
  name = "Immich"
}

data "uptimekuma_monitor_http" "dawarich" {
  name = "Dawarich"
}

data "uptimekuma_monitor_http" "jellyfin" {
  name = "Jellyfin"
}

data "uptimekuma_monitor_http" "navidrome" {
  name = "Navidrome"
}

data "uptimekuma_monitor_http" "stirling-pdf" {
  name = "Stirling PDF"
}

data "uptimekuma_monitor_http" "home-assistant" {
  name = "Home Assistant"
}

data "uptimekuma_monitor_http" "structurizr" {
  name = "Structurizr"
}

data "uptimekuma_monitor_http" "lute" {
  name = "Lute"
}

data "uptimekuma_monitor_http" "sure" {
  name = "Sure"
}

data "uptimekuma_monitor_http" "mailserver" {
  name = "Mailserver"
}

data "uptimekuma_monitor_http" "webmail" {
  name = "Webmail"
}

data "uptimekuma_monitor_http" "seafile" {
  name = "Seafile"
}

data "uptimekuma_monitor_http" "onlyoffice" {
  name = "OnlyOffice"
}

data "uptimekuma_monitor_http" "paperless" {
  name = "Paperless"
}

data "uptimekuma_monitor_http" "infisical" {
  name = "Infisical"
}

data "uptimekuma_monitor_http" "zitadel" {
  name = "Zitadel"
}

data "uptimekuma_monitor_http" "element-web" {
  name = "Element Web"
}

data "uptimekuma_monitor_http" "synapse" {
  name = "Synapse"
}

data "uptimekuma_monitor_http" "talk-signaling" {
  name = "Talk signaling"
}

data "uptimekuma_monitor_http" "netdata" {
  name = "Netdata"
}

data "uptimekuma_monitor_http" "victoria-metrics" {
  name = "VictoriaMetrics"
}

data "uptimekuma_monitor_http" "vmagent" {
  name = "vmagent"
}

data "uptimekuma_monitor_http" "grafana" {
  name = "Grafana"
}

data "uptimekuma_monitor_http" "uptime-kuma" {
  name = "Uptime Kuma"
}

data "uptimekuma_monitor_http" "gatus" {
  name = "Gatus"
}

data "uptimekuma_monitor_http" "wud" {
  name = "WUD"
}

data "uptimekuma_monitor_http" "homepage" {
  name = "Homepage"
}

data "uptimekuma_monitor_http" "beszel" {
  name = "Beszel"
}

data "uptimekuma_monitor_dns" "technitium-dns" {
  name = "Technitium DNS"
}

data "uptimekuma_monitor_tcp_port" "x3-ui" {
  name = "3x-ui"
}

data "uptimekuma_monitor_tcp_port" "forgejo-ssh" {
  name = "Gitea SSH"
}

data "uptimekuma_monitor_tcp_port" "xray-inbound" {
  name = "Xray inbound"
}


locals {
  imported_http = {
    "technitium-http"  = data.uptimekuma_monitor_http.technitium-http.id
    "traefik"          = data.uptimekuma_monitor_http.traefik.id
    "jitsi-meet"       = data.uptimekuma_monitor_http.jitsi-meet.id
    "mermaid"          = data.uptimekuma_monitor_http.mermaid.id
    "nextcloud"        = data.uptimekuma_monitor_http.nextcloud.id
    "forgejo"          = data.uptimekuma_monitor_http.forgejo.id
    "code-server"      = data.uptimekuma_monitor_http.code-server.id
    "authentik"        = data.uptimekuma_monitor_http.authentik.id
    "localai"          = data.uptimekuma_monitor_http.localai.id
    "immich"           = data.uptimekuma_monitor_http.immich.id
    "dawarich"         = data.uptimekuma_monitor_http.dawarich.id
    "jellyfin"         = data.uptimekuma_monitor_http.jellyfin.id
    "navidrome"        = data.uptimekuma_monitor_http.navidrome.id
    "stirling-pdf"     = data.uptimekuma_monitor_http.stirling-pdf.id
    "home-assistant"   = data.uptimekuma_monitor_http.home-assistant.id
    "structurizr"      = data.uptimekuma_monitor_http.structurizr.id
    "lute"             = data.uptimekuma_monitor_http.lute.id
    "sure"             = data.uptimekuma_monitor_http.sure.id
    "mailserver"       = data.uptimekuma_monitor_http.mailserver.id
    "webmail"          = data.uptimekuma_monitor_http.webmail.id
    "seafile"          = data.uptimekuma_monitor_http.seafile.id
    "onlyoffice"       = data.uptimekuma_monitor_http.onlyoffice.id
    "paperless"        = data.uptimekuma_monitor_http.paperless.id
    "infisical"        = data.uptimekuma_monitor_http.infisical.id
    "zitadel"          = data.uptimekuma_monitor_http.zitadel.id
    "element-web"      = data.uptimekuma_monitor_http.element-web.id
    "synapse"          = data.uptimekuma_monitor_http.synapse.id
    "talk-signaling"   = data.uptimekuma_monitor_http.talk-signaling.id
    "netdata"          = data.uptimekuma_monitor_http.netdata.id
    "victoria-metrics" = data.uptimekuma_monitor_http.victoria-metrics.id
    "vmagent"          = data.uptimekuma_monitor_http.vmagent.id
    "grafana"          = data.uptimekuma_monitor_http.grafana.id
    "uptime-kuma"      = data.uptimekuma_monitor_http.uptime-kuma.id
    "gatus"            = data.uptimekuma_monitor_http.gatus.id
    "wud"              = data.uptimekuma_monitor_http.wud.id
    "homepage"         = data.uptimekuma_monitor_http.homepage.id
    "beszel"           = data.uptimekuma_monitor_http.beszel.id
  }

  imported_dns = {
    "technitium-dns" = data.uptimekuma_monitor_dns.technitium-dns.id
  }

  imported_tcp = {
    "x3-ui"        = data.uptimekuma_monitor_tcp_port.x3-ui.id
    "forgejo-ssh"  = data.uptimekuma_monitor_tcp_port.forgejo-ssh.id
    "xray-inbound" = data.uptimekuma_monitor_tcp_port.xray-inbound.id
  }

}

import {
  for_each = local.imported_http
  to       = uptimekuma_monitor_http.monitor[each.key]
  id       = each.value
}

import {
  for_each = local.imported_dns
  to       = uptimekuma_monitor_dns.monitor[each.key]
  id       = each.value
}

import {
  for_each = local.imported_tcp
  to       = uptimekuma_monitor_tcp_port.monitor[each.key]
  id       = each.value
}

