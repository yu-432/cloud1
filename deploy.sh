#!/bin/bash
set -e  # エラー時に停止

echo "===== Cloud-1 自動デプロイ開始 ====="

# Phase 1: Terraform でインフラ構築
echo "Phase 1: インフラ構築中..."
cd terraform
terraform init -input=false
terraform apply -auto-approve

# EC2のIPアドレスを取得
EC2_IP=$(terraform output -raw instance_public_ip)
echo "EC2 IP: $EC2_IP"

# Phase 2: EC2起動待ち
echo "Phase 2: EC2起動待機中（60秒）..."
sleep 60

# SSH接続テスト
echo "SSH接続テスト..."
ssh -i ~/.ssh/cloud1/id_rsa_cloud1 -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$EC2_IP "echo 'SSH OK'" || {
  echo "SSH接続失敗。さらに30秒待機..."
  sleep 30
  ssh -i ~/.ssh/cloud1/id_rsa_cloud1 -o StrictHostKeyChecking=no ubuntu@$EC2_IP "echo 'SSH OK'"
}

# Phase 3: Ansible でデプロイ
echo "Phase 3: Ansible デプロイ中..."
cd ../ansible

# inventory.ini を動的生成
cat > inventory.ini << EOF
[cloud1]
$EC2_IP ansible_ssh_private_key_file=~/.ssh/cloud1/id_rsa_cloud1

[cloud1:vars]
ansible_user=ubuntu
ansible_python_interpreter=/usr/bin/python3
EOF

# Ansible実行
ansible-playbook playbook.yml

# 完了メッセージ
echo ""
echo "===== デプロイ完了 ====="
echo "WordPress: https://$EC2_IP"
echo "phpMyAdmin: https://$EC2_IP/phpmyadmin/"
echo "SSH: ssh -i ~/.ssh/cloud1/id_rsa_cloud1 ubuntu@$EC2_IP"
echo ""
echo "⚠️ 作業終了後は 'terraform destroy' を忘れずに！"
