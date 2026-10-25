output "certificate_id" {
  description = "Сертификат в Certificate Manager"
  value       = yandex_cm_certificate.yc_wildcard.id
}

output "domains" {
  description = "Домены сертификата"
  value       = yandex_cm_certificate.yc_wildcard.domains
}

output "status" {
  description = "Статус выпуска: VALIDATING, ISSUED, RENEWING"
  value       = yandex_cm_certificate.yc_wildcard.status
}

output "not_after" {
  description = "Конец срока действия"
  value       = yandex_cm_certificate.yc_wildcard.not_after
}

output "challenge" {
  description = "DNS-запись, которой подтверждается владение доменом"
  value = [
    for challenge in yandex_cm_certificate.yc_wildcard.challenges : {
      name  = challenge.dns_name
      type  = challenge.dns_type
      value = challenge.dns_value
    }
  ]
}
