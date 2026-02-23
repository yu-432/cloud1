SHELL := /bin/bash
.PHONY: all deploy infra wait provision destroy ssh ssm plan status help

TF_DIR  := terraform
ANS_DIR := ansible

# -----------------------------------------------
# デフォルト: ヘルプ表示
# -----------------------------------------------
all: help

# -----------------------------------------------
# フルデプロイ: 3フェーズを順番に実行
# -----------------------------------------------
deploy: infra wait provision  ## フルデプロイ (terraform apply + SSM待機 + ansible)

# -----------------------------------------------
# Phase 1: Terraform でインフラ構築
# -----------------------------------------------
infra:  ## AWSインフラ構築 (terraform apply)
	@echo "===== Phase 1: インフラ構築 ====="
	cd $(TF_DIR) && terraform init -input=false && terraform apply -auto-approve

plan:  ## Terraformの変更プレビュー (terraform plan)
	cd $(TF_DIR) && terraform init -input=false && terraform plan

# -----------------------------------------------
# Phase 2: SSM Agent オンライン待機
# terraform output からインスタンスIDを取得して確認ループ
# -----------------------------------------------
wait:  ## SSM Agent がオンラインになるまで待機
	@echo "===== Phase 2: SSM Agent オンライン待機 ====="
	@INSTANCE_ID=$$(cd $(TF_DIR) && terraform output -raw instance_id); \
	MAX_ATTEMPTS=30; ATTEMPT=0; STATUS="None"; \
	while [ $$ATTEMPT -lt $$MAX_ATTEMPTS ]; do \
	  ATTEMPT=$$((ATTEMPT + 1)); \
	  STATUS=$$(aws ssm describe-instance-information \
	    --filters "Key=InstanceIds,Values=$$INSTANCE_ID" \
	    --query "InstanceInformationList[0].PingStatus" \
	    --output text 2>/dev/null || echo "None"); \
	  if [ "$$STATUS" = "Online" ]; then \
	    echo "✅ SSM Agent オンライン確認 (試行 $$ATTEMPT/$$MAX_ATTEMPTS)"; \
	    exit 0; \
	  fi; \
	  echo "  SSM Agent 待機中... ($$ATTEMPT/$$MAX_ATTEMPTS) status=$$STATUS"; \
	  sleep 10; \
	done; \
	echo "❌ SSM Agent がオンラインになりませんでした"; \
	exit 1

# -----------------------------------------------
# Phase 3: Ansible でデプロイ
# terraform output からIP・IDを取得して inventory.ini を動的生成
# -----------------------------------------------
provision:  ## Ansibleでデプロイ (inventory自動生成 + ansible-playbook)
	@echo "===== Phase 3: Ansible デプロイ ====="
	@EC2_IP=$$(cd $(TF_DIR) && terraform output -raw instance_public_ip); \
	INSTANCE_ID=$$(cd $(TF_DIR) && terraform output -raw instance_id); \
	SSM_BUCKET=$$(cd $(TF_DIR) && terraform output -raw ssm_bucket_name); \
	printf '[cloud1]\n%s ansible_connection=aws_ssm ansible_aws_ssm_region=ap-northeast-1 ansible_aws_ssm_bucket_name=%s\n\n[cloud1:vars]\nansible_python_interpreter=/usr/bin/python3\n' \
	  "$$INSTANCE_ID" "$$SSM_BUCKET" > $(ANS_DIR)/inventory.ini; \
	echo "  inventory.ini 生成完了 (host: $$INSTANCE_ID, bucket: $$SSM_BUCKET)"; \
	cd $(ANS_DIR) && ansible-galaxy collection install community.aws && OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES ansible-playbook playbook.yml --extra-vars "ec2_public_ip=$$EC2_IP"

# -----------------------------------------------
# インフラ破棄（確認プロンプトあり）
# -----------------------------------------------
destroy:  ## AWSインフラを破棄 (terraform destroy)
	@read -p "⚠️  本当にインフラを破棄しますか？ [y/N]: " CONFIRM; \
	if [ "$$CONFIRM" = "y" ] || [ "$$CONFIRM" = "Y" ]; then \
	  cd $(TF_DIR) && terraform destroy; \
	else \
	  echo "キャンセルしました"; \
	fi

# -----------------------------------------------
# 接続コマンド
# -----------------------------------------------

ssm:  ## SSMセッションで直接接続
	@INSTANCE_ID=$$(cd $(TF_DIR) && terraform output -raw instance_id); \
	echo "接続先: $$INSTANCE_ID"; \
	aws ssm start-session --target "$$INSTANCE_ID"

# -----------------------------------------------
# 状態確認
# -----------------------------------------------
status:  ## EC2・SSM Agentの現在状態を表示
	@echo "===== Terraform出力 ====="
	@cd $(TF_DIR) && terraform output 2>/dev/null || echo "  (stateなし)"
	@echo ""
	@echo "===== SSM Agent 状態 ====="
	@INSTANCE_ID=$$(cd $(TF_DIR) && terraform output -raw instance_id 2>/dev/null); \
	if [ -n "$$INSTANCE_ID" ] && [ "$$INSTANCE_ID" != "" ]; then \
	  aws ssm describe-instance-information \
	    --filters "Key=InstanceIds,Values=$$INSTANCE_ID" \
	    --query "InstanceInformationList[0].{PingStatus:PingStatus,IP:IPAddress,OS:PlatformName,AgentVersion:AgentVersion}" \
	    --output table 2>/dev/null || echo "  (SSM情報取得失敗)"; \
	else \
	  echo "  (インスタンスIDが取得できません)"; \
	fi

# -----------------------------------------------
# ヘルプ: ## コメントからコマンド一覧を自動生成
# -----------------------------------------------
help:  ## 利用可能なコマンド一覧を表示
	@echo "Cloud-1 デプロイ管理"
	@echo ""
	@echo "使い方: make [target]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*##"}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "例:"
	@echo "  make deploy       # インフラ構築からWordPressデプロイまで一括実行"
	@echo "  make infra        # Terraformだけ実行（Ansibleはまだ）"
	@echo "  make provision    # Ansibleだけ再実行（インフラは既にある前提）"
	@echo "  make ssm          # デプロイ済みサーバーにSSM接続"
	@echo "  make destroy      # 課金を止める"
