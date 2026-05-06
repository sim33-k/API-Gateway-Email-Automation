variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
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

variable "ansible_playbook_path" {
  description = "Path to Ansible playbook"
  type        = string
}

variable "ansible_inventory_path" {
  description = "Path to Ansible inventory template"
  type        = string
}

variable "private_key_output_path" {
  description = "Path where private key will be saved"
  type        = string
}

variable "inventory_output_path" {
  description = "Path where inventory file will be generated"
  type        = string
}

variable "jenkins_template_s3_bucket" {
	description = "S3 bucket used by the Jenkins template sync jobs"
	type        = string
}

variable "jenkins_bitbucket_app_password_secret_id" {
  description = "AWS Secrets Manager secret name or ARN that stores the Bitbucket app password"
  type        = string
  default     = ""
}
