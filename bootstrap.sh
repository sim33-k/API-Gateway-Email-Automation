#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script: Provisions infrastructure with Terraform
# Terraform creates secrets in Secrets Manager automatically

echo "=== API Gateway Email Automation Bootstrap ==="
echo ""

# Check if .env.local exists
if [ ! -f ".env.local" ]; then
  echo "❌ .env.local not found. Create it first:"
  echo "   cp .env.example .env.local"
  echo "   # Edit .env.local with your actual values"
  exit 1
fi

# Source environment variables
source .env.local

# Validate required variables
REQUIRED_VARS=(
  "TF_VAR_your_ip"
  "TF_VAR_ami_id"
  "TF_VAR_instance_type"
  "TF_VAR_key_pair_name"
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

