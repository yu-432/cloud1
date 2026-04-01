.PHONY: all setup deploy infra wait provision destroy ssh ssm plan status help multi

TF_DIR  := terraform
ANS_DIR := ansible

# multi が引数にあれば2台、なければ1台
COUNT := $(if $(filter multi,$(MAKECMDGOALS)),2,1)

# -----------------------------------------------
# デフォルト: ヘルプ表示
# -----------------------------------------------
all: help

# -----------------------------------------------
# セットアップ: 初回利用時に secrets.yml を作成
# -----------------------------------------------
setup:  ## 初回セットアップ (secrets.yml.example → secrets.yml をコピー)
	@if [ -f $(ANS_DIR)/vars/secrets.yml ]; then \
	  echo "✅ $(ANS_DIR)/vars/secrets.yml は既に存在します"; \
	else \
	  cp $(ANS_DIR)/vars/secrets.yml.example $(ANS_DIR)/vars/secrets.yml; \
	  echo "✅ $(ANS_DIR)/vars/secrets.yml を作成しました"; \
	  echo "⚠️  パスワードなどを編集してください: $(ANS_DIR)/vars/secrets.yml"; \
	fi

# -----------------------------------------------
# フルデプロイ: 3フェーズを順番に実行
# 使い方: make deploy        (1台)
#         make deploy multi   (2台)
# -----------------------------------------------
deploy: infra wait provision  ## フルデプロイ (terraform apply + SSM待機 + ansible)

multi:  ## deploy と併用して2台構成にする (make deploy multi)
	@:

# -----------------------------------------------
# Phase 1: Terraform でインフラ構築
# -----------------------------------------------
infra:  ## AWSインフラ構築 (terraform apply)
	@echo "===== Phase 1: インフラ構築 ($(COUNT)台) ====="
	cd $(TF_DIR) && terraform init -input=false && terraform apply -auto-approve -var="instance_count=$(COUNT)"

plan:  ## Terraformの変更プレビュー (terraform plan)
	cd $(TF_DIR) && terraform init -input=false && terraform plan -var="instance_count=$(COUNT)"

# -----------------------------------------------
# Phase 2: SSM Agent オンライン待機
# terraform output から全インスタンスIDを取得して各々確認
# -----------------------------------------------
wait:  ## SSM Agent がオンラインになるまで待機
	@echo "===== Phase 2: SSM Agent オンライン待機 ====="
	@INSTANCE_IDS=$$(cd $(TF_DIR) && terraform output -json instance_ids | jq -r '.[]'); \
	for INSTANCE_ID in $$INSTANCE_IDS; do \
	  echo "  待機中: $$INSTANCE_ID"; \
	  MAX_ATTEMPTS=30; ATTEMPT=0; STATUS="None"; \
	  while [ $$ATTEMPT -lt $$MAX_ATTEMPTS ]; do \
	    ATTEMPT=$$((ATTEMPT + 1)); \
	    STATUS=$$(aws ssm describe-instance-information \
	      --filters "Key=InstanceIds,Values=$$INSTANCE_ID" \
	      --query "InstanceInformationList[0].PingStatus" \
	      --output text 2>/dev/null || echo "None"); \
	    if [ "$$STATUS" = "Online" ]; then \
	      echo "✅ $$INSTANCE_ID オンライン確認 (試行 $$ATTEMPT/$$MAX_ATTEMPTS)"; \
	      break; \
	    fi; \
	    echo "    SSM Agent 待機中... ($$ATTEMPT/$$MAX_ATTEMPTS) status=$$STATUS"; \
	    sleep 10; \
	  done; \
	  if [ "$$STATUS" != "Online" ]; then \
	    echo "❌ $$INSTANCE_ID がオンラインになりませんでした"; \
	    exit 1; \
	  fi; \
	done

# -----------------------------------------------
# Phase 3: Ansible でデプロイ
# terraform output から全IP・IDを取得して inventory.ini を動的生成
# -----------------------------------------------
provision:  ## Ansibleでデプロイ (inventory自動生成 + ansible-playbook)
	@echo "===== Phase 3: Ansible デプロイ ====="
	@SSM_BUCKET=$$(cd $(TF_DIR) && terraform output -raw ssm_bucket_name); \
	INSTANCE_IDS=$$(cd $(TF_DIR) && terraform output -json instance_ids | jq -r '.[]'); \
	EC2_IPS=$$(cd $(TF_DIR) && terraform output -json instance_public_ips | jq -r '.[]'); \
	printf '[cloud1]\n' > $(ANS_DIR)/inventory.ini; \
	set -- $$EC2_IPS; \
	for INSTANCE_ID in $$INSTANCE_IDS; do \
	  IP=$$1; shift; \
	  printf '%s ansible_connection=aws_ssm ansible_aws_ssm_region=ap-northeast-1 ansible_aws_ssm_bucket_name=%s ec2_public_ip=%s\n' \
	    "$$INSTANCE_ID" "$$SSM_BUCKET" "$$IP" >> $(ANS_DIR)/inventory.ini; \
	done; \
	printf '\n[cloud1:vars]\nansible_python_interpreter=/usr/bin/python3\n' >> $(ANS_DIR)/inventory.ini; \
	echo "  inventory.ini 生成完了 ($(COUNT)台, bucket: $$SSM_BUCKET)"; \
	cat $(ANS_DIR)/inventory.ini; \
	cd $(ANS_DIR) && ansible-galaxy collection install community.aws && OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES ansible-playbook playbook.yml

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

ssm:  ## SSMセッションで直接接続 (1台目)
	@INSTANCE_ID=$$(cd $(TF_DIR) && terraform output -json instance_ids | jq -r '.[0]'); \
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
	@INSTANCE_IDS=$$(cd $(TF_DIR) && terraform output -json instance_ids 2>/dev/null | jq -r '.[]'); \
	if [ -n "$$INSTANCE_IDS" ]; then \
	  for INSTANCE_ID in $$INSTANCE_IDS; do \
	    echo "--- $$INSTANCE_ID ---"; \
	    aws ssm describe-instance-information \
	      --filters "Key=InstanceIds,Values=$$INSTANCE_ID" \
	      --query "InstanceInformationList[0].{PingStatus:PingStatus,IP:IPAddress,OS:PlatformName,AgentVersion:AgentVersion}" \
	      --output table 2>/dev/null || echo "  (SSM情報取得失敗)"; \
	  done; \
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
	@echo "  make deploy         # 1台でフルデプロイ"
	@echo "  make deploy multi   # 2台で並行デプロイ"
	@echo "  make infra          # Terraformだけ実行"
	@echo "  make provision      # Ansibleだけ再実行"
	@echo "  make ssm            # デプロイ済みサーバーにSSM接続"
	@echo "  make destroy        # 課金を止める"
