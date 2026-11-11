terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Plan-only assessment configuration.
  # Do not use these settings as a substitute for
  # real authentication in production.
  skip_credentials_validation = true
  skip_requesting_account_id   = true
  skip_metadata_api_check      = true
}
