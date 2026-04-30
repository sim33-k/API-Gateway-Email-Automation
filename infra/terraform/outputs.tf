output "jenkins_public_ip" {
  value = aws_instance.jenkins.public_ip
}

output "jenkins_private_key_pem" {
  value     = tls_private_key.jenkins.private_key_pem
  sensitive = true
}

# Writes the inventory file for Ansible
resource "local_file" "ansible_inventory" {
  content  = <<-EOF
    [jenkins]
    ${aws_instance.jenkins.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/your-key.pem
  EOF
  filename = "${path.module}/../ansible/inventory.ini"
}