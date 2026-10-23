output "nodes" {
  description = "Узлы: суффикс → адреса и зона"
  value = {
    for name, instance in yandex_compute_instance.node : name => {
      zone        = instance.zone
      public_ip   = instance.network_interface[0].nat_ip_address
      internal_ip = instance.network_interface[0].ip_address
    }
  }
}

output "api_fqdn" {
  description = "Адрес kube-api: его надо добавить в SAN сертификата apiserver"
  value       = local.api_fqdn
}

output "api_address" {
  description = "Статический адрес балансировщика"
  value       = yandex_vpc_address.api.external_ipv4_address[0].address
}

output "dns_zone" {
  description = "Публичная зона кластера в Cloud DNS"
  value       = yandex_dns_zone.cluster.zone
}

output "dns_delegation_ns" {
  description = "NS-серверы Cloud DNS, которыми подзона делегируется в авторитетной зоне домена"
  value       = ["ns1.yandexcloud.net.", "ns2.yandexcloud.net."]
}

output "kube_api_endpoint" {
  description = "Значение server в kubeconfig"
  value       = "https://${local.api_fqdn}:${local.api_port}"
}
