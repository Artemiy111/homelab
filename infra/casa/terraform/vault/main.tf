terraform {
  required_version = "~> 1.16"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
  }
}

provider "vault" {
  address = "https://vault.${local.domain}"
}

# Политики приложений. Подкаталог без явного source terraform не грузит,
# поэтому он подключён как модуль.
module "policies" {
  source = "./policies"
}
