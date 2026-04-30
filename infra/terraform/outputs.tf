output "jenkins_public_ip" {
  value = aws_instance.jenkins.public_ip
}

output "jenkins_private_key_pem" {
  value     = tls_private_key.jenkins.private_key_pem
  sensitive = true
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