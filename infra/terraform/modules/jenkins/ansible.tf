// required_providers moved to main.tf; module-level providers are declared there
# Save the private key inside the project
resource "local_file" "ansible_private_key" {
  content         = tls_private_key.jenkins.private_key_pem
  filename        = var.private_key_output_path
  file_permission = "0400"
  depends_on      = [tls_private_key.jenkins]
}

# Write inventory with correct user and key path
resource "local_file" "ansible_inventory" {
  content = <<-EOF
[jenkins]
${aws_instance.jenkins.public_ip} ansible_user=ec2-user ansible_ssh_private_key_file=${var.private_key_output_path}
  EOF

  filename   = var.inventory_output_path
  depends_on = [aws_instance.jenkins, local_file.ansible_private_key]
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
      secret_id="$${TF_VAR_jenkins_bitbucket_app_password_secret_id:-}"
      if [ -z "$secret_id" ]; then
        echo "TF_VAR_jenkins_bitbucket_app_password_secret_id is required" >&2
        exit 1
      fi

      ansible-playbook \
        -i ${var.inventory_output_path} \
        ${var.ansible_playbook_path} \
        --extra-vars "jenkins_bitbucket_app_password_secret_id=$secret_id" \
        --ssh-extra-args='-o StrictHostKeyChecking=no'
    EOF
  }
}
