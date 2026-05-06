variable "aws_region" {
	description = "AWS region"
	type        = string
	default     = "ap-southeast-1"
}

variable "your_ip" {
	description = "Your IP address for SSH and Jenkins UI access"
	type        = string
}

variable "ami_id" {
	description = "AMI ID for Jenkins server"
	type        = string
}

variable "instance_type" {
	description = "EC2 instance type"
	type        = string
}

variable "key_pair_name" {
	description = "Name of the SSH key pair"
	type        = string
}

variable "jenkins_template_s3_bucket" {
	description = "S3 bucket used by the Jenkins template sync jobs"
	type        = string
	default     = "digiratina-api-gw-automation-ap-southeast-1-20260424-9f3c"
}

variable "jenkins_bitbucket_app_password_secret_id" {
	description = "AWS Secrets Manager secret name or ARN that stores the Bitbucket app password"
	type        = string
	default     = ""
}

variable "groq_api_key_secret_id" {
	description = "AWS Secrets Manager secret name for GROQ API key"
	type        = string
	default     = "digiratina-groq-api-key"
}

variable "groq_api_key_value" {
	description = "The actual GROQ API key value"
	type        = string
	sensitive   = true
}

variable "lambda_parser_name" {
	description = "Name of the parser Lambda function"
	type        = string
	default     = "api-gw-email-parser"
}

variable "lambda_patcher_name" {
	description = "Name of the patcher Lambda function"
	type        = string
	default     = "api-gw-json-patcher"
}

variable "jenkins_bitbucket_app_password_value" {
	description = "The actual Bitbucket app password value"
	type        = string
	sensitive   = true
}