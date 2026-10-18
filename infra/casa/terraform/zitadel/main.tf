terraform {
  required_version = "~> 1.16"

  required_providers {
    zitadel = {
      source  = "zitadel/zitadel"
      version = "~> 3.8"
    }
  }
}

provider "zitadel" {
  domain = "id.${var.domain}"

  jwt_profile_file = pathexpand(var.jwt_profile_file)
}
