# Makefile for Fleet Management Infrastructure

.PHONY: help init plan apply destroy validate format clean status logs backup restore

# Colors for output
GREEN  := \033[0;32m
YELLOW := \033[0;33m
RED    := \033[0;31m
NC     := \033[0m # No Color

# Default AWS region
AWS_REGION ?= us-east-1
ENVIRONMENT ?= production

help: ## Show this help message
	@echo "$(GREEN)Fleet Management Infrastructure - Available Commands$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""

init: ## Initialize Terraform
	@echo "$(GREEN)Initializing Terraform...$(NC)"
	terraform init
	@echo "$(GREEN)✅ Terraform initialized successfully!$(NC)"

validate: ## Validate Terraform configuration
	@echo "$(GREEN)Validating configuration...$(NC)"
	terraform validate
	terraform fmt -check -recursive
	@echo "$(GREEN)✅ Configuration is valid!$(NC)"

format: ## Format Terraform files
	@echo "$(GREEN)Formatting Terraform files...$(NC)"
	terraform fmt -recursive
	@echo "$(GREEN)✅ Files formatted!$(NC)"

plan: ## Create Terraform execution plan
	@echo "$(GREEN)Creating execution plan...$(NC)"
	terraform plan -out=tfplan
	@echo "$(GREEN)✅ Plan created! Review and run 'make apply' to deploy$(NC)"

apply: ## Apply Terraform changes
	@echo "$(YELLOW)⚠️  This will create/modify infrastructure!$(NC)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		terraform apply tfplan; \
		echo "$(GREEN)✅ Infrastructure deployed!$(NC)"; \
	else \
		echo "$(RED)❌ Deployment cancelled$(NC)"; \
	fi

apply-auto: ## Apply Terraform changes without confirmation (use with caution!)
	@echo "$(GREEN)Applying changes automatically...$(NC)"
	terraform apply -auto-approve
	@echo "$(GREEN)✅ Infrastructure deployed!$(NC)"

destroy: ## Destroy all infrastructure
	@echo "$(RED)⚠️  WARNING: This will DESTROY all infrastructure!$(NC)"
	@echo "$(RED)All data will be lost!$(NC)"
	@read -p "Type 'destroy' to confirm: " confirm; \
	if [ "$$confirm" = "destroy" ]; then \
		terraform destroy; \
		echo "$(GREEN)✅ Infrastructure destroyed$(NC)"; \
	else \
		echo "$(RED)❌ Destruction cancelled$(NC)"; \
	fi

status: ## Show infrastructure status
	@echo "$(GREEN)Infrastructure Status:$(NC)"
	@echo ""
	@echo "$(YELLOW)Terraform State:$(NC)"
	@terraform show -json | jq -r '.values.root_module.resources | length' | xargs -I {} echo "  Resources: {}"
	@echo ""
	@echo "$(YELLOW)ECS Service:$(NC)"
	@aws ecs describe-services \
		--cluster $(ENVIRONMENT)-fleet-cluster \
		--services $(ENVIRONMENT)-fleet-api \
		--query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}' \
		--output table 2>/dev/null || echo "  Not found or not deployed yet"
	@echo ""
	@echo "$(YELLOW)RDS Database:$(NC)"
	@aws rds describe-db-instances \
		--db-instance-identifier $(ENVIRONMENT)-fleet-postgres \
		--query 'DBInstances[0].{Status:DBInstanceStatus,Engine:Engine,Class:DBInstanceClass}' \
		--output table 2>/dev/null || echo "  Not found or not deployed yet"

outputs: ## Show Terraform outputs
	@echo "$(GREEN)Terraform Outputs:$(NC)"
	@terraform output

logs: ## Tail ECS application logs
	@echo "$(GREEN)Tailing application logs (Ctrl+C to stop)...$(NC)"
	@aws logs tail /ecs/$(ENVIRONMENT)-fleet-api --follow --format short

logs-recent: ## Show recent logs (last 30 minutes)
	@echo "$(GREEN)Recent logs (last 30 minutes):$(NC)"
	@aws logs tail /ecs/$(ENVIRONMENT)-fleet-api --since 30m --format short

clean: ## Clean up local files
	@echo "$(GREEN)Cleaning up local files...$(NC)"
	rm -f tfplan
	rm -f .terraform.lock.hcl
	@echo "$(GREEN)✅ Cleanup complete!$(NC)"

setup-backend: ## Create S3 backend and DynamoDB table
	@echo "$(GREEN)Setting up Terraform backend...$(NC)"
	@aws s3 mb s3://fleet-management-terraform-state --region $(AWS_REGION) || true
	@aws s3api put-bucket-versioning \
		--bucket fleet-management-terraform-state \
		--versioning-configuration Status=Enabled
	@aws dynamodb create-table \
		--table-name fleet-terraform-locks \
		--attribute-definitions AttributeName=LockID,AttributeType=S \
		--key-schema AttributeName=LockID,KeyType=HASH \
		--billing-mode PAY_PER_REQUEST \
		--region $(AWS_REGION) 2>/dev/null || true
	@echo "$(GREEN)✅ Backend setup complete!$(NC)"

scale-up: ## Scale ECS service up (increases desired count by 2)
	@echo "$(GREEN)Scaling ECS service up...$(NC)"
	@CURRENT=$$(aws ecs describe-services \
		--cluster $(ENVIRONMENT)-fleet-cluster \
		--services $(ENVIRONMENT)-fleet-api \
		--query 'services[0].desiredCount' \
		--output text); \
	NEW=$$((CURRENT + 2)); \
	aws ecs update-service \
		--cluster $(ENVIRONMENT)-fleet-cluster \
		--service $(ENVIRONMENT)-fleet-api \
		--desired-count $$NEW
	@echo "$(GREEN)✅ Service scaled up!$(NC)"

scale-down: ## Scale ECS service down (decreases desired count by 2)
	@echo "$(GREEN)Scaling ECS service down...$(NC)"
	@CURRENT=$$(aws ecs describe-services \
		--cluster $(ENVIRONMENT)-fleet-cluster \
		--services $(ENVIRONMENT)-fleet-api \
		--query 'services[0].desiredCount' \
		--output text); \
	NEW=$$((CURRENT - 2)); \
	if [ $$NEW -lt 1 ]; then NEW=1; fi; \
	aws ecs update-service \
		--cluster $(ENVIRONMENT)-fleet-cluster \
		--service $(ENVIRONMENT)-fleet-api \
		--desired-count $$NEW
	@echo "$(GREEN)✅ Service scaled down!$(NC)"

restart: ## Restart ECS service (force new deployment)
	@echo "$(GREEN)Restarting ECS service...$(NC)"
	@aws ecs update-service \
		--cluster $(ENVIRONMENT)-fleet-cluster \
		--service $(ENVIRONMENT)-fleet-api \
		--force-new-deployment
	@echo "$(GREEN)✅ Service restart initiated!$(NC)"

backup: ## Create manual database snapshot
	@echo "$(GREEN)Creating database snapshot...$(NC)"
	@SNAPSHOT_ID="manual-backup-$$(date +%Y%m%d-%H%M%S)"; \
	aws rds create-db-snapshot \
		--db-instance-identifier $(ENVIRONMENT)-fleet-postgres \
		--db-snapshot-identifier $$SNAPSHOT_ID; \
	echo "$(GREEN)✅ Snapshot created: $$SNAPSHOT_ID$(NC)"

list-backups: ## List database snapshots
	@echo "$(GREEN)Database Snapshots:$(NC)"
	@aws rds describe-db-snapshots \
		--db-instance-identifier $(ENVIRONMENT)-fleet-postgres \
		--query 'DBSnapshots[*].[DBSnapshotIdentifier,Status,SnapshotCreateTime]' \
		--output table

health: ## Check API health
	@echo "$(GREEN)Checking API health...$(NC)"
	@API_URL=$$(terraform output -raw api_endpoint 2>/dev/null); \
	if [ -z "$$API_URL" ]; then \
		echo "$(RED)❌ Cannot get API endpoint. Is infrastructure deployed?$(NC)"; \
		exit 1; \
	fi; \
	HTTP_CODE=$$(curl -s -o /dev/null -w "%{http_code}" http://$$API_URL/health); \
	if [ "$$HTTP_CODE" = "200" ]; then \
		echo "$(GREEN)✅ API is healthy! (HTTP $$HTTP_CODE)$(NC)"; \
	else \
		echo "$(RED)❌ API is unhealthy! (HTTP $$HTTP_CODE)$(NC)"; \
		exit 1; \
	fi

cost: ## Estimate monthly costs (requires infracost)
	@which infracost > /dev/null || (echo "$(RED)infracost not installed. Visit: https://www.infracost.io/docs/$(NC)" && exit 1)
	@echo "$(GREEN)Estimating monthly costs...$(NC)"
	@infracost breakdown --path .

graph: ## Generate infrastructure dependency graph
	@echo "$(GREEN)Generating dependency graph...$(NC)"
	@terraform graph | dot -Tpng > infrastructure-graph.png
	@echo "$(GREEN)✅ Graph saved to infrastructure-graph.png$(NC)"

ssh-task: ## SSH into running ECS task
	@echo "$(GREEN)Connecting to ECS task...$(NC)"
	@TASK_ID=$$(aws ecs list-tasks \
		--cluster $(ENVIRONMENT)-fleet-cluster \
		--service-name $(ENVIRONMENT)-fleet-api \
		--query 'taskArns[0]' \
		--output text | cut -d'/' -f3); \
	if [ -z "$$TASK_ID" ]; then \
		echo "$(RED)❌ No running tasks found$(NC)"; \
		exit 1; \
	fi; \
	aws ecs execute-command \
		--cluster $(ENVIRONMENT)-fleet-cluster \
		--task $$TASK_ID \
		--container api \
		--interactive \
		--command "/bin/sh"

migrate: ## Run database migrations
	@echo "$(GREEN)Running database migrations...$(NC)"
	@TASK_ID=$$(aws ecs list-tasks \
		--cluster $(ENVIRONMENT)-fleet-cluster \
		--service-name $(ENVIRONMENT)-fleet-api \
		--query 'taskArns[0]' \
		--output text | cut -d'/' -f3); \
	aws ecs execute-command \
		--cluster $(ENVIRONMENT)-fleet-cluster \
		--task $$TASK_ID \
		--container api \
		--command "npm run migrate"

update-config: ## Copy terraform.tfvars.example to terraform.tfvars
	@if [ -f terraform.tfvars ]; then \
		echo "$(YELLOW)⚠️  terraform.tfvars already exists!$(NC)"; \
		read -p "Overwrite? [y/N] " -n 1 -r; \
		echo; \
		if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
			cp terraform.tfvars.example terraform.tfvars; \
			echo "$(GREEN)✅ Configuration file created$(NC)"; \
		fi \
	else \
		cp terraform.tfvars.example terraform.tfvars; \
		echo "$(GREEN)✅ Configuration file created$(NC)"; \
		echo "$(YELLOW)⚠️  Please edit terraform.tfvars with your values$(NC)"; \
	fi

dashboard: ## Open CloudWatch dashboard
	@echo "$(GREEN)Opening CloudWatch dashboard...$(NC)"
	@open "https://console.aws.amazon.com/cloudwatch/home?region=$(AWS_REGION)#dashboards:name=$(ENVIRONMENT)-fleet-dashboard" || \
	xdg-open "https://console.aws.amazon.com/cloudwatch/home?region=$(AWS_REGION)#dashboards:name=$(ENVIRONMENT)-fleet-dashboard" || \
	echo "Visit: https://console.aws.amazon.com/cloudwatch/home?region=$(AWS_REGION)#dashboards:name=$(ENVIRONMENT)-fleet-dashboard"

check-deps: ## Check if required tools are installed
	@echo "$(GREEN)Checking dependencies...$(NC)"
	@which terraform > /dev/null && echo "$(GREEN)✅ Terraform installed$(NC)" || echo "$(RED)❌ Terraform not found$(NC)"
	@which aws > /dev/null && echo "$(GREEN)✅ AWS CLI installed$(NC)" || echo "$(RED)❌ AWS CLI not found$(NC)"
	@which docker > /dev/null && echo "$(GREEN)✅ Docker installed$(NC)" || echo "$(RED)❌ Docker not found$(NC)"
	@which jq > /dev/null && echo "$(GREEN)✅ jq installed$(NC)" || echo "$(YELLOW)⚠️  jq not found (optional)$(NC)"
	@aws sts get-caller-identity > /dev/null 2>&1 && echo "$(GREEN)✅ AWS credentials configured$(NC)" || echo "$(RED)❌ AWS credentials not configured$(NC)"

quick-start: check-deps setup-backend update-config ## Quick start setup (run this first!)
	@echo ""
	@echo "$(GREEN)========================================$(NC)"
	@echo "$(GREEN)✅ Quick start setup complete!$(NC)"
	@echo "$(GREEN)========================================$(NC)"
	@echo ""
	@echo "$(YELLOW)Next steps:$(NC)"
	@echo "  1. Edit terraform.tfvars with your values"
	@echo "  2. Run: make init"
	@echo "  3. Run: make plan"
	@echo "  4. Run: make apply"
	@echo ""
```

**Save this as**: `fleet-infrastructure/Makefile`

---

## 🎉 All 25 Files Complete!

You now have a complete, production-ready Terraform infrastructure for your Fleet Management System!

### 📁 Final Directory Structure
```
fleet-infrastructure/
├── .gitignore
├── main.tf
├── variables.tf
├── terraform.tfvars.example
├── README.md
├── DEPLOYMENT_GUIDE.md
├── Makefile
└── modules/
    ├── vpc/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── rds/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── ecs/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── s3/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── elasticache/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── monitoring/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf