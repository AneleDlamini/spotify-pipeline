# This file defines the SSM parameters for storing sensitive information used by the Spotify ingest Lambda function, such as the Client ID, Client Secret, and Refresh Token.

######################## Define SSM Parameters #########################

# Secure parameters used by the Spotify ingest Lambda function - Client ID.
resource "aws_ssm_parameter" "spotify_client_id" {
  name  = "/${var.project_name}/spotify/client_id"
  type  = "SecureString"
  value = "placeholder"

  lifecycle {
    ignore_changes = [value]
  }
}

# Secure parameters used by the Spotify ingest Lambda function - Client Secret.
resource "aws_ssm_parameter" "spotify_client_secret" {
  name  = "/${var.project_name}/spotify/client_secret"
  type  = "SecureString"
  value = "placeholder"

  lifecycle {
    ignore_changes = [value]
  }
}

# Secure parameters used by the Spotify ingest Lambda function - Refresh Token.
resource "aws_ssm_parameter" "spotify_refresh_token" {
  name  = "/${var.project_name}/spotify/refresh_token"
  type  = "SecureString"
  value = "placeholder"

  lifecycle {
    ignore_changes = [value]
  }
}
