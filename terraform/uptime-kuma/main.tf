terraform {
  required_version = "~> 1.16"

  required_providers {
    external = {
      source  = "hashicorp/external"
      version = "~> 2.4"
    }
    uptimekuma = {
      source  = "breml/uptimekuma"
      version = "~> 0.4"
    }
  }
}

provider "uptimekuma" {
  endpoint    = "https://kuma.${var.domain}"
  timeout     = "30s"
  max_retries = 5
}
