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

output "ssm_bucket_name" {
  description = "Ansible SSMファイル転送用S3バケット"
  value       = aws_s3_bucket.ssm_bucket.bucket
}
