output "instance_public_ip" {
  description = "EC2インスタンスのパブリックIPアドレス"
  value       = aws_instance.cloud1.public_ip
}

output "instance_id" {
  description = "EC2インスタンスID"
  value       = aws_instance.cloud1.id
}

output "ssh_command" {
  description = "SSH接続コマンド"
  value       = "ssh -i ~/.ssh/cloud1/id_rsa_cloud1 ubuntu@${aws_instance.cloud1.public_ip}"
}