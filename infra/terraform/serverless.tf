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

# IAM Policy for Lambda to access S3, Secrets Manager, and CloudWatch
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

# SES Receipt Rule Set for ap-south-1 style inbound email handling
resource "aws_ses_receipt_rule_set" "apigw" {
  rule_set_name = "default-rule-set"
}

# Activate the receipt rule set
resource "aws_ses_active_receipt_rule_set" "apigw" {
  rule_set_name = aws_ses_receipt_rule_set.apigw.rule_set_name
}

# Receipt rule that stores raw emails in S3 and invokes the parser Lambda
resource "aws_ses_receipt_rule" "apigw_requests" {
  name          = "apigw-requests-rule"
  rule_set_name = aws_ses_receipt_rule_set.apigw.rule_set_name
  enabled       = true
  scan_enabled  = true

  recipients = ["apigw-requests@simaakniyaz.site"]

  s3_action {
    position          = 1
    bucket_name       = aws_s3_bucket.automation.id
    object_key_prefix = "raw-emails/"
  }

  lambda_action {
    position        = 2
    function_arn    = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.lambda_parser_name}"
    invocation_type = "Event"
  }
}

# Allow SES to invoke the parser Lambda
resource "aws_lambda_permission" "allow_ses_invoke_parser" {
  statement_id   = "AllowSESToInvokeParser"
  action         = "lambda:InvokeFunction"
  function_name  = var.lambda_parser_name
  principal      = "ses.amazonaws.com"
  source_arn     = aws_ses_receipt_rule.apigw_requests.arn
  source_account = data.aws_caller_identity.current.account_id
}

# Outputs
output "s3_bucket_name" {
  description = "S3 bucket for automation workflow"
  value       = aws_s3_bucket.automation.id
}

output "ses_receipt_rule_set_name" {
  description = "Active SES receipt rule set name"
  value       = aws_ses_receipt_rule_set.apigw.rule_set_name
}

output "lambda_role_arn" {
  description = "IAM role ARN for Lambda functions"
  value       = aws_iam_role.lambda_automation.arn
}

output "ses_receipt_rule_name" {
  description = "SES receipt rule name"
  value       = aws_ses_receipt_rule.apigw_requests.name
}
