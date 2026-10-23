locals {
  domain  = "biplane.casa"
  host_ip = "192.168.1.254"

  delegations = {
    "yc.clusters" = ["ns1.yandexcloud.net", "ns2.yandexcloud.net"]
  }

  delegation_records = merge([
    for subdomain, nameservers in local.delegations : {
      for nameserver in nameservers :
      "${subdomain}/${nameserver}" => {
        subdomain  = subdomain
        nameserver = nameserver
      }
    }
  ]...)
}
