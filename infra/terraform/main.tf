provider "aws" {
    region = var.aws_region
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

