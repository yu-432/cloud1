terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# -----------------------------------------------
# SSH鍵ペア
# ローカルで作った公開鍵をAWSに登録する
# -----------------------------------------------
resource "aws_key_pair" "cloud1" {
  key_name   = "cloud1-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

# -----------------------------------------------
# セキュリティグループ（ファイアウォール）
# どのポートへのアクセスを許可するかを定義
# -----------------------------------------------
resource "aws_security_group" "cloud1_sg" {
  name        = "cloud1-sg"
  description = "Security group for Cloud-1 project"

  # SSH (22番ポート) — サーバー管理用
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # HTTP (80番ポート) — Web通常アクセス（HTTPSへリダイレクト用）
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS (443番ポート) — Web暗号化アクセス
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # アウトバウンド（外向き通信）はすべて許可
  # EC2からインターネットへの通信（パッケージダウンロード等）に必要
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "cloud1-sg"
  }
}

# -----------------------------------------------
# Ubuntu 20.04 LTS の AMI（ディスクイメージ）を検索
# AWSには多数のAMIがあるので、フィルタで絞り込む
# -----------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical (Ubuntu公式) のAWSアカウントID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# -----------------------------------------------
# EC2インスタンス（仮想マシン本体）
# -----------------------------------------------
resource "aws_instance" "cloud1" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.cloud1.key_name
  vpc_security_group_ids = [aws_security_group.cloud1_sg.id]

  # スポットインスタンスとして起動（コスト削減）
  instance_market_options {
    market_type = "spot"
    spot_options {
      spot_instance_type = "one-time"
    }
  }

  # ルートボリューム（メインのディスク）
  root_block_device {
    volume_size = 20    # 20GB（Docker イメージ + データ用に余裕を持たせる）
    volume_type = "gp3" # 汎用SSD（gp3は無料枠対象）
  }

  tags = {
    Name = "cloud1-inception"
  }
}
