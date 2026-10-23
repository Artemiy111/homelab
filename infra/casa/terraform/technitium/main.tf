terraform {
  required_version = "~> 1.16"

  required_providers {
    technitium = {
      source  = "darkhonor/technitium"
      version = "~> 1.2"
    }
  }
}

provider "technitium" {
  server_url = "https://dns.${local.domain}"
  api_token  = ""
}
