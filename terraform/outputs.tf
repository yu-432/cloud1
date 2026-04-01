output "instance_public_ips" {
  description = "EC2インスタンスのパブリックIPアドレス一覧"
  value       = aws_instance.cloud1[*].public_ip
}

output "instance_ids" {
  description = "EC2インスタンスID一覧"
  value       = aws_instance.cloud1[*].id
}

output "ssm_bucket_name" {
  description = "Ansible SSMファイル転送用S3バケット"
  value       = aws_s3_bucket.ssm_bucket.bucket
}
