output "instance_public_ip" {
  description = "EC2インスタンスのパブリックIPアドレス"
  value       = aws_instance.cloud1.public_ip
}

output "instance_id" {
  description = "EC2インスタンスID"
  value       = aws_instance.cloud1.id
}

output "ssm_command" {
  description = "SSMセッション接続コマンド"
  value       = "aws ssm start-session --target ${aws_instance.cloud1.id}"
}

output "ssm_ssh_command" {
  description = "SSMトンネル経由SSH接続コマンド"
  value       = "ssh -i ~/.ssh/cloud1/id_rsa_cloud1 -o ProxyCommand='aws ssm start-session --target ${aws_instance.cloud1.id} --document-name AWS-StartSSHSession --parameters portNumber=%p' ubuntu@${aws_instance.cloud1.id}"
}
