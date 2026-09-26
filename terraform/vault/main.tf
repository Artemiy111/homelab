terraform {
  required_version = "~> 1.16"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
  }
}

# Провайдер настраивается окружением: address из VAULT_ADDR, token из
# ~/.vault-token. https://developer.hashicorp.com/terraform/providers/hashicorp/vault
provider "vault" {}
