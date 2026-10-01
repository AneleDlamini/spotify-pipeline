# This file is used to define the outputs of the Terraform configuration.

# We want to output the name of the bucket created
output "raw_bucket_name" {
  value       = aws_s3_bucket.raw_data.bucket
  description = "The name of the raw data S3 bucket."
}
# This output provides the ARN of the IAM role assumed by the Lambda function
output "lambda_role_arn" {
  value       = aws_iam_role.lambda.arn
  description = "The ARN of the IAM role for the Lambda function."
}

# This output provides the name of the IAM role assumed by the Lambda function
output "ecr_repository_url" {
  value  = aws_ecr_repository.ingest.repository_url
  description = "The URL of the ECR repository for the Lambda function."
}