terraform {
  required_version = "~> 1.16"

  backend "s3" {
    bucket = "terraform-state"
    key    = "clusters/casa/zitadel/terraform.tfstate"
    region = "us-east-1"

    endpoints = {
      s3 = "https://s3.biplane.casa"
    }

    use_path_style              = true
    use_lockfile                = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
  }

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
