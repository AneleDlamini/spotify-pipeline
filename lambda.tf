# This file defines the Lambda functions, their associated ECR repositories, and CloudWatch log groups for the Spotify data pipeline.


########################### Define ECR Repositories ###########################

# ECR repository holding the ingest Lambda image.
resource "aws_ecr_repository" "ingest" {
  name                 = "${var.project_name}-ingest"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ECR lifecycle policy to keep only the 5 most recent images for the ingest lambda function.
resource "aws_ecr_lifecycle_policy" "ingest" {
  repository = aws_ecr_repository.ingest.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the 5 most recent images"
      selection = {
        tagStatus      = "tagged"
        tagPatternList = ["*"]
        countType      = "imageCountMoreThan"
        countNumber    = 5
      }
      action = { type = "expire" }
    }]
  })
}

########################## Define Lambda Functions ##########################

# Resource defining the ingest Lambda function.
resource "aws_lambda_function" "ingest" {
  function_name = "${var.project_name}-ingest"
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.ingest.repository_url}:${var.image_tag}"
  timeout       = 60
  memory_size   = 256

  environment {
    variables = {
      PARAM_PREFIX = "/${var.project_name}"
      RAW_BUCKET   = aws_s3_bucket.raw_data.bucket
    }
  }
}

# Resource defining the transform Lambda function.
resource "aws_lambda_function" "transform" {
  function_name = "${var.project_name}-transform"
  role          = aws_iam_role.lambda-transform.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.ingest.repository_url}:${var.image_tag}"
  timeout       = 60
  memory_size   = 256

  image_config {                      # configure the entry point for the Lambda function
    command = ["transform.handler"]
  }
}

# Resource granting permission for the S3 bucket to invoke the transform Lambda function.
resource "aws_lambda_permission" "s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.transform.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.raw_data.arn
}

############################ Define CloudWatch Log Groups ############################

# CloudWatch log group for the ingest Lambda function with a retention period of 14 days.
resource "aws_cloudwatch_log_group" "ingest" {
  name              = "/aws/lambda/${aws_lambda_function.ingest.function_name}"
  retention_in_days = 14
}

# CloudWatch log group for the transform Lambda function with a retention period of 14 days.
resource "aws_cloudwatch_log_group" "transform" {
  name              = "/aws/lambda/${aws_lambda_function.transform.function_name}"
  retention_in_days = 14
}

