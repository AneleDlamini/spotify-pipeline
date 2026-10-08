# This file defines the EventBridge rule and permissions for scheduling the ingest Lambda function in the Spotify data pipeline.

######################## Define EventBridge Rule #########################

# Schedule the ingest Lambda function every six hours.
resource "aws_cloudwatch_event_rule" "ingest_schedule" {
  name                = "${var.project_name}-ingest"
  description         = "Schedule for triggering the Spotify ingest Lambda function"
  schedule_expression = "rate(6 hours)"
}

# Grant permission for EventBridge to invoke the ingest Lambda function.
resource "aws_lambda_permission" "events" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ingest_schedule.arn
}

