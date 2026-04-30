terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
    region = var.aws_region
}

resource "tls_private_key" "jenkins" {
    algorithm = "RSA"
    rsa_bits  = 4096
}

resource "aws_key_pair" "jenkins" {
    key_name   = var.key_pair_name
    public_key = tls_private_key.jenkins.public_key_openssh
}

# Security groups
resource "aws_security_group" "jenkins" {
    name = "jenkins-sg"
    description = "Jenkins server"

    # Ingress rules
    ingress {
        description = "SSH"
        from_port = 22
        to_port = 22
        protocol = "tcp"
        
        # I want only my IP allowed
        cidr_blocks = [ var.your_ip ]
    }

    ingress {
        description = "SSH"
        from_port = 8080
        to_port = 8080
        protocol = "tcp"
        
        # I want only my IP allowed
        cidr_blocks = [ var.your_ip ]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = [ "0.0.0.0/0" ]
    }
}

# AWS EC2 for Jenkins
resource "aws_instance" "jenkins" {
    ami = var.ami_id
    instance_type = var.instance_type
    key_name = aws_key_pair.jenkins.key_name
    vpc_security_group_ids = [ aws_security_group.jenkins.id ]

    root_block_device {
        volume_size = 8
        volume_type = "gp3"
    }

    tags = {
      Name = "jenkins-server"
      Project = "api-gw-automation"
    }
  
}

# Save the private key inside the project
resource "local_file" "ansible_private_key" {
  content         = tls_private_key.jenkins.private_key_pem
  filename        = "${path.module}/../ansible/jenkins.pem"
  file_permission = "0400"
  depends_on      = [tls_private_key.jenkins]
}

# Write inventory with correct user and key path
resource "local_file" "ansible_inventory" {
  content  = <<-EOF
[jenkins]
${aws_instance.jenkins.public_ip} ansible_user=ec2-user ansible_ssh_private_key_file=${path.module}/../ansible/jenkins.pem
  EOF
  filename = "${path.module}/../ansible/inventory.ini"
}

# Auto-run Ansible after everything is ready
resource "null_resource" "run_ansible" {
  depends_on = [
    aws_instance.jenkins,
    local_file.ansible_private_key,
    local_file.ansible_inventory
  ]

  provisioner "local-exec" {
    command = <<-EOF
      ansible-playbook \
        -i ${path.module}/../ansible/inventory.ini \
        ${path.module}/../ansible/playbook.yml \
        --ssh-extra-args='-o StrictHostKeyChecking=no'
    EOF
  }
}

