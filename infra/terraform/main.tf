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

