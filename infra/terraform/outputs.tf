output "jenkins_public_ip" {
  value = aws_instance.jenkins.public_ip
}

output "jenkins_private_key_pem" {
  value     = tls_private_key.jenkins.private_key_pem
  sensitive = true
}