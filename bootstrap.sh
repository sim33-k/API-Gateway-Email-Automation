#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script: Provisions infrastructure with Terraform
# Infrastructure inputs come from infra/terraform/terraform.tfvars

echo "=== API Gateway Email Automation Bootstrap ==="
echo ""

# Check if .env.local exists
if [ ! -f ".env.local" ]; then
  echo "❌ .env.local not found. Create it first:"
  echo "   cp .env.example .env.local"
  echo "   # Edit .env.local with your secret values only"
  exit 1
fi

# Source secret values only
source .env.local

# Validate required variables
REQUIRED_VARS=(
  "TF_VAR_groq_api_key_value"
  "TF_VAR_jenkins_bitbucket_app_password_value"
)

echo "Checking variables..."
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "❌ Missing: $var"
    exit 1
  fi
done

echo "✓ All variables set"
echo ""

# Run terraform
echo "=== Provisioning with Terraform ==="
cd infra/terraform
terraform init
terraform apply -auto-approve

echo ""
echo "=== Bootstrap Complete ==="
echo ""
jenkins_ip=$(terraform output jenkins_public_ip -raw)
echo "Jenkins URL: http://${jenkins_ip}:8080"
echo "SSH: ssh -i ../../infra/ansible/jenkins.pem ec2-user@${jenkins_ip}"
echo ""
echo "Admin password saved in: .generated/jenkins-admin-password"

