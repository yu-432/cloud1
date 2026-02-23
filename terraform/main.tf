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
# IAMロール・インスタンスプロファイル（SSM用）
# EC2が SSM Agent → AWS API と通信するために必要
# -----------------------------------------------
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

resource "aws_iam_instance_profile" "cloud1_ssm" {
  name = "cloud1-ssm-profile"
  role = aws_iam_role.cloud1_ssm.name
}

# -----------------------------------------------
# AnsibleがSSM経由でファイルを転送（24KB以上）するためのS3バケット
# amazon.aws.aws_ssmプラグインの必須要件
# -----------------------------------------------
resource "aws_s3_bucket" "ssm_bucket" {
  bucket_prefix = "cloud1-ssm-ansible-"
  force_destroy = true # インフラ破棄時にバケット内にファイルがあっても削除する
}

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

# -----------------------------------------------
# セキュリティグループ（ファイアウォール）
# どのポートへのアクセスを許可するかを定義
# SSH (22) は SSMトンネル経由のため不要 → インバウンドなし
# -----------------------------------------------
resource "aws_security_group" "cloud1_sg" {
  name        = "cloud1-sg"
  description = "Security group for Cloud-1 project"

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
# Ubuntu 24.04 LTS の AMI（ディスクイメージ）を検索
# AWSには多数のAMIがあるので、フィルタで絞り込む
# -----------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (Ubuntu公式) のAWSアカウントID

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

  vpc_security_group_ids = [aws_security_group.cloud1_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.cloud1_ssm.name

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
