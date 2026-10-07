# This file defines the S3 bucket and public access block for storing raw data in the Spotify data pipeline.

# This resource creates an S3 bucket for storing raw data.
resource "aws_s3_bucket" "raw_data" {
  bucket_prefix = "${var.project_name}-raw-data-"
  force_destroy = true
}

# Block public access to the raw data bucket.
resource "aws_s3_bucket_public_access_block" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


resource "aws_s3_bucket_notification" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.transform.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix      = "recently_played/"
    filter_suffix      = ".json"
  }

  depends_on = [aws_lambda_permission.s3]
}
