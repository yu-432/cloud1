variable "aws_region" {
  description = "AWSリージョン"
  type        = string
  default     = "ap-northeast-1"  # 東京リージョン
}

variable "instance_type" {
  description = "EC2インスタンスタイプ"
  type        = string
  default     = "t3.micro"  # 無料枠対象（東京リージョン対応）
}

