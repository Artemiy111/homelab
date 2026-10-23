terraform {
  required_version = "~> 1.16"

  required_providers {
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.29"
    }
  }
}

provider "tailscale" {}

locals {
  domain  = "biplane.casa"
  host_ip = "192.168.1.254"
}
