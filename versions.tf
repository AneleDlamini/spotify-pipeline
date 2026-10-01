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

  backend "s3" {
    key            = "spotify-pipeline/terraform.tfstate"        # The key (path) within the S3 bucket where the Terraform state file will be stored.
    region         = "us-east-1"          # The AWS region where the S3 bucket is located, specified by the variable aws_region.
    encrypt        = true                     # Enable server-side encryption for the state file in S3.
    use_lockfile   = true
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

