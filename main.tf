# This file is used to define the resources that will be created in AWS using Terraform.

# This resource creates an S3 bucket in AWS for storing raw data.
resource "aws_s3_bucket" "raw_data" {
  bucket_prefix = "${var.project_name}-raw-data-" # bucket name prefixed with the project name and a unique identifier
  force_destroy = true                            # del bucket even if it contains objects
}

# This resource is used to block public access to the S3 bucket created above.
resource "aws_s3_bucket_public_access_block" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id # This references the S3 bucket created above.

  # The following settings are used to block public access to the S3 bucket.
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
# This resource creates an SSM parameter in AWS for storing the Spotify client ID securely.
resource "aws_ssm_parameter" "spotify_client_id" {
  name  = "/${var.project_name}/spotify/client_id"
  type  = "SecureString"                                 
  value = "placeholder"      

  lifecycle {
    ignore_changes = [value] # Ignore changes to the value of the parameter outside of Terraform
  }
}
# This resource creates an SSM parameter in AWS for storing the Spotify client secret securely.
resource "aws_ssm_parameter" "spotify_client_secret" {
  name  = "/${var.project_name}/spotify/client_secret"
  type  = "SecureString"                                 
  value = "placeholder" # The value of the parameter is set to a placeholder. In a real-world scenario, this should be replaced with the actual Spotify client secret.

  lifecycle {
    ignore_changes = [value] 
  }
}

# This resource creates an SSM parameter in AWS for storing the Spotify refresh token securely.
resource "aws_ssm_parameter" "spotify_refresh_token"{
  name = "/${var.project_name}/spotify/refresh_token"
  type = "SecureString"
  value = "placeholder"

  lifecycle {
    ignore_changes =[value]
  }
}


# WHO can wear the badge (trust policy)
data aws_iam_policy_document "lambda_trust" { 
  statement {
    actions   = ["sts:AssumeRole"] # Lambda to assume this role
  
    principals {
      type        = "Service" # Role can be assumed by an AWS service.
      identifiers = ["lambda.amazonaws.com"] # The AWS Lambda service is allowed to assume this role.
    }
  }
}

# This resource creates an IAM role in AWS for the Lambda function to assume.   
resource "aws_iam_role" "lambda" {
  name               = "${var.project_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json # The trust policy defined above is used to allow the Lambda service to assume this role.
}

# This resource creates an IAM policy in AWS that allows the Lambda function to write data to the S3 bucket + get Spotify keys from SSM 
# WHAT the basge unlocks (permissions policy)
data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    sid       = "WriteRawData" # This statement allows the Lambda function to write (raw) data to the S3 bucket
    actions   = ["s3:PutObject"] 
    resources = ["${aws_s3_bucket.raw_data.arn}/*"] # Where to put the object/data (which bucket)
  }

  statement {
    sid = "ReadSpotifyKeys"
    actions   = ["ssm:GetParameter"] # This statement allows the Lambda function to read the Spotify client ID and secret from the SSM parameters.
    resources = [
      aws_ssm_parameter.spotify_client_id.arn,
      aws_ssm_parameter.spotify_client_secret.arn,
      aws_ssm_parameter.spotify_refresh_token.arn
    ]
  }
}

# This resource creates an IAM role policy in AWS that attaches the permissions policy to the IAM role created for the Lambda function.
resource "aws_iam_role_policy" "lambda" {
  name   = "${var.project_name}-lambda-permissions" 
  role   = aws_iam_role.lambda.id # The IAM role created above is associated with this policy.
  policy = data.aws_iam_policy_document.lambda_permissions.json # Permissions policy attached to the IAM role.
}

# This resource creates an IAM role policy attachment in AWS that attaches the AWS managed policy for Lambda basic execution to the IAM role created for the Lambda function.
# This policy allows the Lambda function to write logs to CloudWatch for error logging
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name # The IAM role created above is associated with this policy attachment.
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" # allows Lambda to write logs to CloudWatch
}

# This resource creates an ECR repository in AWS for storing Docker images used by the Lambda function.
resource "aws_ecr_repository" "ingest" {
  name = "${var.project_name}-ingest"
  image_tag_mutability = "MUTABLE" # allows image tags to be overwritten

  image_scanning_configuration {
    scan_on_push = true # enables image scanning on push
  }
}

# This resource creates an ECR lifecycle policy in AWS that defines rules for managing the images in the ECR repository created above.
resource "aws_ecr_lifecycle_policy" "ingest" {
  repository = aws_ecr_repository.ingest.name 

  policy = jsonencode({
  rules = [{
      rulePriority = 1 # The priority of the rule. Lower numbers indicate higher priority.
      description  = "Keep only the 5 most recent images" # This rule keeps only the 5 most recent images in the ECR repository and expires older images.
      selection    = {
        tagStatus    = "tagged"
        tagPatternList = ["*"] # This rule applies to all tagged images in the ECR repository.
        countType    = "imageCountMoreThan"
        countNumber  = 5
      }
      action = {type = "expire"} # This action expires images that match the selection criteria.
    }]
  })
}

# This resource creates a Lambda function in AWS that is packaged as a Docker image and uses the ECR repository created.
resource "aws_lambda_function" "ingest" {
  function_name = "${var.project_name}-ingest"
  role          = aws_iam_role.lambda.arn # The IAM role created above is associated with this Lambda function.
  package_type  = "Image" # The Lambda function is packaged as a Docker image.
  image_uri     = "${aws_ecr_repository.ingest.repository_url}:v1" # Pulls the latest Docker image from the ECR repository created for the Lambda function.
  timeout       = 60 # Max execution time for the Lambda function (seconds)
  memory_size   = 256 # Memory allocated to the Lambda function (MB)

  environment {
    variables = {
      PARAM_PREFIX = "/${var.project_name}" # The prefix for the SSM parameters that store the Spotify client ID and secret.
      RAW_BUCKET   = aws_s3_bucket.raw_data.bucket # The name of the S3 bucket created for storing raw data.
    }
  }
}

# This resource creates a CloudWatch log group in AWS for the Lambda function created above. The log group is used to store logs generated by the Lambda function during its execution.
resource "aws_cloudwatch_log_group" "ingest" {
  name              = "/aws/lambda/${aws_lambda_function.ingest.function_name}" # Name of the log group, which is based on the name of the Lambda function.
  retention_in_days = 14 # The number of days to retain logs in CloudWatch before they are automatically deleted.
}

# Schedule the Lambda function to run every 6 hours using CloudWatch Events. This resource creates a CloudWatch Event Rule that triggers the Lambda function on a schedule.
resource "aws_cloudwatch_event_rule" "ingest_schedule" {
  name                = "${var.project_name}-ingest"
  description         = "Schedule for triggering the Spotify ingest Lambda function"
  schedule_expression = "rate(6 hours)" # The Lambda function will be triggered every 6 hours.
}

# Event trigger for the Lambda function. This resource creates a CloudWatch Event Target that associates the CloudWatch Event Rule created above with the Lambda function.
resource "aws_lambda_permission" "events" {
  statement_id  = "AllowExecutionFromEventBridge" # A unique identifier for the permission statement.
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "events.amazonaws.com" # The principal that is allowed to invoke the Lambda function is the CloudWatch Events service.
  source_arn    = aws_cloudwatch_event_rule.ingest_schedule.arn # The ARN of the CloudWatch Event Rule that triggers the Lambda function.
}
