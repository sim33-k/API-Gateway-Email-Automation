# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Create secrets in AWS Secrets Manager from terraform variables
resource "aws_secretsmanager_secret" "groq_api_key" {
  name = var.groq_api_key_secret_id
}

resource "aws_secretsmanager_secret_version" "groq_api_key" {
  secret_id     = aws_secretsmanager_secret.groq_api_key.id
  secret_string = var.groq_api_key_value
}

resource "aws_secretsmanager_secret" "bitbucket_app_password" {
  name = var.jenkins_bitbucket_app_password_secret_id
}

resource "aws_secretsmanager_secret_version" "bitbucket_app_password" {
  secret_id     = aws_secretsmanager_secret.bitbucket_app_password.id
  secret_string = var.jenkins_bitbucket_app_password_value
}

# S3 Buckets for API Gateway automation
resource "aws_s3_bucket" "automation" {
  bucket = var.jenkins_template_s3_bucket
}

resource "aws_s3_bucket_versioning" "automation" {
  bucket = aws_s3_bucket.automation.id
  versioning_configuration {
    status = "Enabled"
  }
}

# SNS Topic for Lambda notifications
resource "aws_sns_topic" "automation" {
  name = "api-gw-automation-notifications"
}

# IAM Role for Lambda Functions
resource "aws_iam_role" "lambda_automation" {
  name = "lambda-api-gw-automation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# IAM Policy for Lambda to access S3, Secrets Manager, SNS, and CloudWatch
resource "aws_iam_role_policy" "lambda_automation" {
  name = "lambda-api-gw-automation-policy"
  role = aws_iam_role.lambda_automation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.automation.arn,
          "${aws_s3_bucket.automation.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.groq_api_key_secret_id}*",
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.jenkins_bitbucket_app_password_secret_id}*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.automation.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.lambda_patcher_name}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*"
        ]
      }
    ]
  })
}

# SES Configuration Set (for tracking email delivery)
resource "aws_ses_configuration_set" "automation" {
  name = "api-gw-automation"
}

# SES Event Destination for SNS notifications
resource "aws_ses_event_destination" "automation" {
  name                   = "api-gw-automation-events"
  configuration_set_name = aws_ses_configuration_set.automation.name
  enabled                = true
  matching_types         = ["Bounce", "Complaint", "Delivery"]
  type                   = "SNS"

  sns_destination {
    topic_arn = aws_sns_topic.automation.arn
  }
}

# Outputs
output "s3_bucket_name" {
  description = "S3 bucket for automation workflow"
  value       = aws_s3_bucket.automation.id
}

output "sns_topic_arn" {
  description = "SNS topic for notifications"
  value       = aws_sns_topic.automation.arn
}

output "lambda_role_arn" {
  description = "IAM role ARN for Lambda functions"
  value       = aws_iam_role.lambda_automation.arn
}

output "ses_configuration_set_name" {
  description = "SES configuration set name"
  value       = aws_ses_configuration_set.automation.name
}
