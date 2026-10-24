terraform {
  required_version = "~> 1.16"

  backend "s3" {
    bucket = "terraform-state"
    key    = "casa/forgejo/terraform.tfstate"
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
    forgejo = {
      source  = "svalabs/forgejo"
      version = "~> 1.6"
    }
  }
}

provider "forgejo" {
  host = "https://forgejo.${var.domain}"
}
