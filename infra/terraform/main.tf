terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Jenkins Module
module "jenkins" {
  source = "./modules/jenkins"

  aws_region                 = var.aws_region
  your_ip                    = var.your_ip
  ami_id                     = var.ami_id
  instance_type              = var.instance_type
  key_pair_name              = var.key_pair_name
  ansible_playbook_path      = "${path.module}/../ansible/playbook.yml"
  ansible_inventory_path     = "${path.module}/../ansible/inventory.ini"
  private_key_output_path    = "${path.module}/../ansible/jenkins.pem"
  inventory_output_path      = "${path.module}/../ansible/inventory.ini"
}

