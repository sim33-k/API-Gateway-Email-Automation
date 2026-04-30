output "jenkins_public_ip" {
  description = "Public IP of Jenkins server"
  value       = aws_instance.jenkins.public_ip
}

output "jenkins_private_key_pem" {
  description = "Private key for Jenkins server"
  value       = tls_private_key.jenkins.private_key_pem
  sensitive   = true
}

output "security_group_id" {
  description = "Security group ID for Jenkins"
  value       = aws_security_group.jenkins.id
}

output "instance_id" {
  description = "Jenkins instance ID"
  value       = aws_instance.jenkins.id
}
