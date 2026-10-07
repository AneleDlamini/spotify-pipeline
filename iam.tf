# This file defines the IAM roles and policies for the Lambda functions used in the Spotify data pipeline.


######################## Define IAM Trust Policy #######################

# Trust policy used by the Lambda roles.
data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}
  
####################### Define IAM Roles #########################

# Resource defining the IAM role for the ingest Lambda function.
resource "aws_iam_role" "lambda" {
  name               = "${var.project_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

# Resource defining the IAM role for the transform Lambda function.
resource "aws_iam_role" "lambda-transform" {
  name               = "${var.project_name}-lambda-transform-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

###################### Define IAM Policies ######################

# Permissions for the ingest Lambda functions.
data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    sid       = "WriteRawData"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.raw_data.arn}/*"]
  }

  statement {
    sid     = "ReadSpotifyKeys"
    actions = ["ssm:GetParameter"]
    resources = [
      aws_ssm_parameter.spotify_client_id.arn,
      aws_ssm_parameter.spotify_client_secret.arn,
      aws_ssm_parameter.spotify_refresh_token.arn,
    ]
  }
}

# Permissions for the transform Lambda functions.
data "aws_iam_policy_document" "lambda_transform_permissions" {
  statement {
    sid       = "ReadRawData"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.raw_data.arn}/*"]
  }
}

########################## Attach Policies to Roles ###########################

# Policy attachments for the Lambda roles.
resource "aws_iam_role_policy" "lambda" {
  name   = "${var.project_name}-lambda-permissions"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

# Policy attachments for the Lambda transform role.
resource "aws_iam_role_policy" "lambda_transform" {
  name   = "${var.project_name}-lambda-transform-permissions"
  role   = aws_iam_role.lambda-transform.id
  policy = data.aws_iam_policy_document.lambda_transform_permissions.json
}

############################## Logging Policies ##############################

# Attach the AWSLambdaBasicExecutionRole policy to the Lambda role for logging.
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach the AWSLambdaBasicExecutionRole policy to the Lambda transform role for logging.
resource "aws_iam_role_policy_attachment" "lambda_transform_logs" {
  role       = aws_iam_role.lambda-transform.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
