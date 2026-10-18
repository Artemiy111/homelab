terraform {
  required_version = "~> 1.16"

  required_providers {
    forgejo = {
      source  = "svalabs/forgejo"
      version = "~> 1.6"
    }
  }
}

provider "forgejo" {
  host = "https://forgejo.${var.domain}"
}
