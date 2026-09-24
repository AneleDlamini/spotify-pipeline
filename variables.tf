# This file is used to define input variables for the Terraform configuration.

variable "aws_region" {
  description = "The AWS region where resources will be created."
  default     = "us-east-1"
  type        = string
}

variable "project_name" {
  description = "The name of the project for tagging purposes."
  default     = "spotify-pipeline"
  type        = string
}