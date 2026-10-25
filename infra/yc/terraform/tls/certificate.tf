resource "yandex_cm_certificate" "yc_wildcard" {
  name        = "yc-wildcard"
  description = "Приложения кластера yc: *.yc.clusters.biplane.casa"
  domains     = [local.domain]

  managed {
    challenge_type  = "DNS_CNAME"
    challenge_count = 1
  }
}

resource "yandex_dns_recordset" "challenge" {
  count   = yandex_cm_certificate.yc_wildcard.managed[0].challenge_count
  zone_id = data.yandex_dns_zone.cluster.id
  name    = yandex_cm_certificate.yc_wildcard.challenges[count.index].dns_name
  type    = yandex_cm_certificate.yc_wildcard.challenges[count.index].dns_type
  data    = [yandex_cm_certificate.yc_wildcard.challenges[count.index].dns_value]
  ttl     = 60
}
