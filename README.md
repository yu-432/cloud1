# Cloud-1

AWS EC2 上に WordPress + phpMyAdmin + MariaDB を Docker コンテナとして自動デプロイする。

インフラ構築は **Terraform**、サーバー構成は **Ansible** で完全自動化。SSHを使わず **AWS SSM** 経由で接続する。

## アーキテクチャ

```
┌─────────────────────────────────────────────────┐
│  AWS EC2 (Ubuntu 24.04 / t3.micro spot)         │
│                                                 │
│  ┌───────────┐  ┌──────────┐  ┌──────────────┐  │
│  │  Nginx    │  │WordPress │  │  phpMyAdmin   │  │
│  │ (TLS:443) │  │ (PHP-FPM)│  │              │  │
│  └─────┬─────┘  └────┬─────┘  └──────┬───────┘  │
│        │              │               │          │
│        │         ┌────┴───────────────┘          │
│        │         │                               │
│        │    ┌────┴─────┐                         │
│        │    │ MariaDB  │                         │
│        │    └──────────┘                         │
│        │                                         │
│  Docker Compose (inception_network)              │
└─────────────────────────────────────────────────┘
```

- **Nginx** - リバースプロキシ + 自己署名TLS証明書
- **WordPress** - PHP-FPM で動作
- **MariaDB** - データベース
- **phpMyAdmin** - `/phpmyadmin/` パスで Nginx 経由アクセス

## 前提条件

- AWS CLI (認証設定済み)
- Terraform
- Ansible + `community.aws` コレクション
- Python 3 + boto3

## セットアップ

```bash
# 1. シークレットファイルを作成し、パスワードを編集
make setup
vim ansible/vars/secrets.yml

# 2. フルデプロイ (Terraform → SSM待機 → Ansible)
make deploy
```

## コマンド一覧

| コマンド | 説明 |
|---|---|
| `make setup` | 初回セットアップ (secrets.yml を作成) |
| `make deploy` | フルデプロイ (インフラ構築 → デプロイ) |
| `make infra` | Terraform のみ実行 |
| `make plan` | Terraform の変更プレビュー |
| `make provision` | Ansible のみ再実行 |
| `make ssm` | SSM セッションで EC2 に接続 |
| `make status` | EC2 / SSM Agent の現在状態を表示 |
| `make destroy` | インフラを破棄 (課金停止) |

## ディレクトリ構成

```
.
├── Makefile              # デプロイ管理
├── terraform/
│   ├── main.tf           # EC2, SG, IAM, S3
│   ├── variables.tf      # リージョン, インスタンスタイプ
│   └── outputs.tf        # IP, インスタンスID等
└── ansible/
    ├── playbook.yml      # メインPlaybook
    ├── ansible.cfg
    ├── vars/
    │   └── secrets.yml   # パスワード等 (git管理外)
    └── roles/
        ├── common/       # Docker / 基盤パッケージ
        └── inception/    # リポジトリクローン, コンテナ起動
```

## セキュリティ

- SSH ポートは閉じており、SSM 経由でのみ接続可能
- データベースは外部公開されない (Docker 内部ネットワークのみ)
- パスワードは Docker secrets で管理
- TLS (自己署名証明書) でHTTPS通信

## デプロイ後のアクセス

```
WordPress:  https://<EC2のパブリックIP>
phpMyAdmin: https://<EC2のパブリックIP>/phpmyadmin/
```

## 注意事項

- スポットインスタンスを使用しているため、AWS により中断される可能性がある
- 使用後は `make destroy` でインフラを破棄し、課金を停止すること
