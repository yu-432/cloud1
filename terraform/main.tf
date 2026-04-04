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

# IAMロール: EC2が SSM Agent → AWS API と通信するために必要
resource "aws_iam_role" "cloud1_ssm" {
  name = "cloud1-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "cloud1-ssm-role"
  }
}

resource "aws_iam_role_policy_attachment" "cloud1_ssm" {
  role       = aws_iam_role.cloud1_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAMロールをEC2に紐づけるためのインスタンスプロファイル
resource "aws_iam_instance_profile" "cloud1_ssm" {
  name = "cloud1-ssm-profile"
  role = aws_iam_role.cloud1_ssm.name
}

# AnsibleがSSM経由で24KB以上のファイルを転送するためのS3バケット
resource "aws_s3_bucket" "ssm_bucket" {
  bucket_prefix = "cloud1-ssm-ansible-"
  force_destroy = true
}

# EC2からS3バケットへの読み書き権限
resource "aws_iam_role_policy" "cloud1_ssm_s3" {
  name = "cloud1-ssm-s3-policy"
  role = aws_iam_role.cloud1_ssm.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetEncryptionConfiguration",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.ssm_bucket.arn,
          "${aws_s3_bucket.ssm_bucket.arn}/*"
        ]
      }
    ]
  })
}

# セキュリティグループ（ファイアウォール）
# SSH (22) は SSMトンネル経由のため不要
resource "aws_security_group" "cloud1_sg" {
  name        = "cloud1-sg"
  description = "Security group for Cloud-1 project"

  # HTTPS
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # アウトバウンドはすべて許可（パッケージダウンロード等に必要）
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

# Ubuntu 24.04 LTS の AMI を検索
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (Ubuntu公式)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# EC2インスタンス
resource "aws_instance" "cloud1" {
  count                  = var.instance_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type

  vpc_security_group_ids = [aws_security_group.cloud1_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.cloud1_ssm.name

  # スポットインスタンス（コスト削減）
  instance_market_options {
    market_type = "spot"
    spot_options {
      spot_instance_type = "one-time"
    }
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "cloud1-inception-${count.index}"
  }
}
