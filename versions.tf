# This file is used to specify the required versions of 
# Terraform and the providers used in this configuration.

terraform {
  required_version = ">= 1.6" # Configuration requires Terraform version 1.6 or higher.

  required_providers {
    aws = {
      source  = "hashicorp/aws" # Configuration requires the AWS provider from HashiCorp.
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region # The AWS region is specified by the variable aws_region, which should be defined in the variables.tf file or provided as an input variable.

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}