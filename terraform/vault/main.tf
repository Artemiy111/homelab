terraform {
  required_version = "~> 1.16"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
  }
}

# Провайдер настраивается окружением, а не кодом: address приходит из
# VAULT_ADDR, token — из ~/.vault-token. Блок объявлен явно, чтобы конфигурация
# провайдера была видна в коде, а не подразумевалась.
provider "vault" {}
