# =============================================================================
# 3Sixty Docker Compose Makefile
# =============================================================================
# Simplifies common Docker Compose operations for 3Sixty deployment
# =============================================================================

.PHONY: help aws-configure aws-login aws-verify aws-logout \
        check-prereqs \
        certs env-check env-create \
        start stop restart clean \
        logs logs-admin logs-discovery logs-mongo logs-nginx logs-ollama logs-opensearch \
        ps health exec-admin exec-mongo \
        pull update rebuild \
        monitoring-start monitoring-stop monitoring-logs \
        vault-start vault-stop \
        oi-agent-start oi-agent-stop \
        opensearch-start opensearch-stop opensearch-logs \
        elasticsearch-start elasticsearch-stop elasticsearch-logs \
        backup restore \
        validate security-scan \
        show-versions

# -----------------------------------------------------------------------------
# Image Version Manifest
# -----------------------------------------------------------------------------
# Load image versions from versions.env (Makefile variable expansion applies,
# so IMAGE_* variables contain fully-resolved URIs when exported to subprocesses).
-include versions.env
export IMAGE_3SIXTY_ADMIN IMAGE_3SIXTY_DISCOVERY IMAGE_SCIM IMAGE_RAG IMAGE_REMOTE_AGENT
export IMAGE_NGINX IMAGE_MONGO IMAGE_OPENSEARCH IMAGE_OPENSEARCH_DASHBOARDS IMAGE_RABBITMQ IMAGE_OLLAMA

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
AWS_REGION := ap-southeast-2
ECR_REGISTRY := 782396859527.dkr.ecr.$(AWS_REGION).amazonaws.com
COMPOSE_FILES := -f docker-compose.yaml
MONITORING_COMPOSE := -f docker-compose.monitoring.yaml
VAULT_COMPOSE := -f docker-compose.vault.yaml
OI_AGENT_COMPOSE := -f docker-compose.oi-agent.yaml
ELASTICSEARCH_COMPOSE := -f docker-compose.elasticsearch.yaml

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------
help: ## Show this help message
	@echo "$(BLUE)===============================================================================$(NC)"
	@echo "$(GREEN)3Sixty Docker Compose Management$(NC)"
	@echo "$(BLUE)===============================================================================$(NC)"
	@echo ""
	@echo "$(YELLOW)AWS Authentication:$(NC)"
	@awk 'BEGIN {FS = ":.*##"; printf ""} /^[a-zA-Z_0-9-]+:.*?##/ { if ($$1 ~ /^aws-/) printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(YELLOW)Environment Setup:$(NC)"
	@awk 'BEGIN {FS = ":.*##"; printf ""} /^[a-zA-Z_0-9-]+:.*?##/ { if ($$1 ~ /^(check-prereqs|certs|env-)/) printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(YELLOW)Service Management:$(NC)"
	@awk 'BEGIN {FS = ":.*##"; printf ""} /^[a-zA-Z_0-9-]+:.*?##/ { if ($$1 ~ /^(start|stop|restart|clean|ps|health)$$/) printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(YELLOW)Logs:$(NC)"
	@awk 'BEGIN {FS = ":.*##"; printf ""} /^[a-zA-Z_0-9-]+:.*?##/ { if ($$1 ~ /^logs/) printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(YELLOW)Updates:$(NC)"
	@awk 'BEGIN {FS = ":.*##"; printf ""} /^[a-zA-Z_0-9-]+:.*?##/ { if ($$1 ~ /^(pull|update|rebuild)/) printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(YELLOW)Optional Services:$(NC)"
	@awk 'BEGIN {FS = ":.*##"; printf ""} /^[a-zA-Z_0-9-]+:.*?##/ { if ($$1 ~ /^(monitoring|vault|oi-agent|opensearch|elasticsearch)/) printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(YELLOW)Utilities:$(NC)"
	@awk 'BEGIN {FS = ":.*##"; printf ""} /^[a-zA-Z_0-9-]+:.*?##/ { if ($$1 ~ /^(backup|restore|validate|security|show-)/) printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""

# -----------------------------------------------------------------------------
# Prerequisites Check
# -----------------------------------------------------------------------------
check-prereqs: ## Check all prerequisites for your platform (run this first!)
	@UNAME=$$(uname -s 2>/dev/null); \
	ARCH=$$(uname -m 2>/dev/null); \
	ERRORS=0; \
	WARNINGS=0; \
	echo "$(BLUE)===============================================================================$(NC)"; \
	echo "$(GREEN)3Sixty Prerequisites Check$(NC)"; \
	echo "$(BLUE)===============================================================================$(NC)"; \
	case "$$UNAME" in \
	  Darwin)               PLATFORM="macOS" ;; \
	  Linux)                PLATFORM="Linux" ;; \
	  MINGW*|MSYS*|CYGWIN*) PLATFORM="Windows / Git Bash" ;; \
	  *)                    PLATFORM="$$UNAME" ;; \
	esac; \
	echo "Platform : $$PLATFORM / $$ARCH"; \
	echo ""; \
	echo "$(YELLOW)Core tools:$(NC)"; \
	if docker info > /dev/null 2>&1; then \
	  echo "  $(GREEN)✓ Docker is running$(NC)"; \
	else \
	  echo "  $(RED)✗ Docker is not running or not installed$(NC)"; \
	  ERRORS=$$((ERRORS+1)); \
	fi; \
	if docker compose version > /dev/null 2>&1; then \
	  echo "  $(GREEN)✓ Docker Compose v2$(NC)"; \
	else \
	  echo "  $(RED)✗ Docker Compose v2 not found$(NC)"; \
	  echo "     Need 'docker compose' (v2), not the legacy 'docker-compose' (v1) plugin."; \
	  ERRORS=$$((ERRORS+1)); \
	fi; \
	if aws --version > /dev/null 2>&1; then \
	  echo "  $(GREEN)✓ AWS CLI$(NC)"; \
	else \
	  echo "  $(RED)✗ AWS CLI not found$(NC)"; \
	  echo "     Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"; \
	  ERRORS=$$((ERRORS+1)); \
	fi; \
	if openssl version > /dev/null 2>&1; then \
	  echo "  $(GREEN)✓ openssl$(NC)"; \
	else \
	  echo "  $(YELLOW)⚠ openssl not found — required for 'make certs'$(NC)"; \
	  WARNINGS=$$((WARNINGS+1)); \
	fi; \
	echo ""; \
	echo "$(YELLOW)Platform-specific checks:$(NC)"; \
	case "$$UNAME" in \
	  Darwin) \
	    if [ "$$ARCH" = "arm64" ]; then \
	      echo "  $(YELLOW)⚠ Apple Silicon (arm64) detected$(NC)"; \
	      echo "     Objective ECR images are amd64-only. Docker Desktop runs them via Rosetta 2"; \
	      echo "     (functional but ~20-30%% slower). Add to ~/.zshrc or ~/.bash_profile:"; \
	      echo "       export DOCKER_DEFAULT_PLATFORM=linux/amd64"; \
	      echo "     dperson/samba has no arm64 image — comment it out in docker-compose.yaml"; \
	      echo "     if you do not need the BFS/NWD network share."; \
	      WARNINGS=$$((WARNINGS+1)); \
	    else \
	      echo "  $(GREEN)✓ Intel Mac (amd64) — no architecture concerns$(NC)"; \
	    fi; \
	    ;; \
	  Linux) \
	    MAP_COUNT=$$(sysctl -n vm.max_map_count 2>/dev/null || echo 0); \
	    if [ "$$MAP_COUNT" -ge 262144 ]; then \
	      echo "  $(GREEN)✓ vm.max_map_count = $$MAP_COUNT (OpenSearch OK)$(NC)"; \
	    else \
	      echo "  $(RED)✗ vm.max_map_count = $$MAP_COUNT (need >= 262144 for OpenSearch)$(NC)"; \
	      echo "     Fix now :  sudo sysctl -w vm.max_map_count=262144"; \
	      echo "     Persist  : echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf"; \
	      ERRORS=$$((ERRORS+1)); \
	    fi; \
	    ;; \
	  MINGW*|MSYS*|CYGWIN*) \
	    echo "  $(GREEN)✓ Running in Git Bash — Makefile targets are supported$(NC)"; \
	    echo "  $(YELLOW)⚠ WSL2 is recommended for full compatibility$(NC)"; \
	    echo "     OpenSearch requires vm.max_map_count=262144."; \
	    echo "     In WSL2: sudo sysctl -w vm.max_map_count=262144"; \
	    echo "     Or in Docker Desktop → Resources → WSL Integration."; \
	    WARNINGS=$$((WARNINGS+1)); \
	    ;; \
	  *) \
	    echo "  $(YELLOW)⚠ Unrecognised platform '$$UNAME' — manual verification required$(NC)"; \
	    WARNINGS=$$((WARNINGS+1)); \
	    ;; \
	esac; \
	echo ""; \
	echo "$(BLUE)===============================================================================$(NC)"; \
	if [ "$$ERRORS" -eq 0 ] && [ "$$WARNINGS" -eq 0 ]; then \
	  echo "$(GREEN)✓ All checks passed — ready to run 'make start'$(NC)"; \
	elif [ "$$ERRORS" -eq 0 ]; then \
	  echo "$(YELLOW)⚠ Ready with $$WARNINGS warning(s) — review notes above$(NC)"; \
	else \
	  echo "$(RED)✗ $$ERRORS error(s) must be resolved before running 'make start'$(NC)"; \
	  exit 1; \
	fi

# -----------------------------------------------------------------------------
# AWS Authentication
# -----------------------------------------------------------------------------
aws-configure: ## Configure AWS credentials (interactive)
	@echo "$(BLUE)Configuring AWS CLI...$(NC)"
	@echo "$(YELLOW)You will be prompted for:$(NC)"
	@echo "  - AWS Access Key ID"
	@echo "  - AWS Secret Access Key"
	@echo "  - Default region: $(AWS_REGION)"
	@echo "  - Default output format: json"
	@echo ""
	@aws configure

aws-login: ## Login to AWS ECR
	@echo "$(BLUE)Logging into AWS ECR...$(NC)"
	@aws ecr get-login-password --region $(AWS_REGION) | \
		docker login --username AWS --password-stdin $(ECR_REGISTRY)
	@echo "$(GREEN)✓ Successfully logged into ECR$(NC)"

aws-verify: ## Verify AWS authentication
	@echo "$(BLUE)Verifying AWS credentials...$(NC)"
	@aws sts get-caller-identity --output table
	@echo "$(GREEN)✓ AWS authentication verified$(NC)"

aws-logout: ## Logout from AWS ECR
	@echo "$(BLUE)Logging out from AWS ECR...$(NC)"
	@docker logout $(ECR_REGISTRY)
	@echo "$(GREEN)✓ Logged out from ECR$(NC)"

# -----------------------------------------------------------------------------
# Environment Setup
# -----------------------------------------------------------------------------
certs: ## Generate self-signed SSL certificates for local development
	@echo "$(BLUE)Generating self-signed SSL certificates...$(NC)"
	@if [ ! -d "nginx/certs" ]; then mkdir -p nginx/certs; fi
	@openssl req -x509 -newkey rsa:2048 -days 365 \
		-nodes \
		-keyout nginx/certs/tls.key \
		-out nginx/certs/tls.crt \
		-subj "/CN=localhost/O=Objective/OU=3Sixty/C=AU"
	@echo "$(GREEN)✓ Certificates generated in nginx/certs/$(NC)"

env-check: ## Check if .env file exists
	@if [ ! -f .env ]; then \
		echo "$(RED)✗ .env file not found!$(NC)"; \
		echo "$(YELLOW)Run 'make env-create' to create from template$(NC)"; \
		exit 1; \
	else \
		echo "$(GREEN)✓ .env file exists$(NC)"; \
	fi

env-create: ## Create .env file from .env.sample
	@if [ -f .env ]; then \
		echo "$(YELLOW)⚠ .env file already exists. Skipping...$(NC)"; \
		echo "$(YELLOW)  To recreate, delete .env first$(NC)"; \
	else \
		echo "$(BLUE)Creating .env from .env.sample...$(NC)"; \
		cp .env.sample .env; \
		echo "$(GREEN)✓ .env file created$(NC)"; \
		echo "$(YELLOW)⚠ IMPORTANT: Edit .env and update all CHANGEME values$(NC)"; \
	fi

# -----------------------------------------------------------------------------
# Service Management
# -----------------------------------------------------------------------------
start: env-check ## Start all core services
	@echo "$(BLUE)Starting 3Sixty services...$(NC)"
	@docker compose $(COMPOSE_FILES) up -d
	@echo "$(GREEN)✓ Services started$(NC)"
	@echo ""
	@echo "$(YELLOW)Access URLs:$(NC)"
	@echo "  Admin UI:      https://localhost/3sixty-admin/"
	@echo "  Discovery UI:  https://localhost/3sixty-discovery/"
	@echo "  OpenSearch:    http://localhost:15601"
	@echo "  RabbitMQ:      http://localhost:15672"
	@echo ""
	@echo "$(YELLOW)Run 'make health' to check service status$(NC)"

stop: ## Stop all services
	@echo "$(BLUE)Stopping services...$(NC)"
	@docker compose $(COMPOSE_FILES) down
	@echo "$(GREEN)✓ Services stopped$(NC)"

restart: ## Restart all services
	@echo "$(BLUE)Restarting services...$(NC)"
	@docker compose $(COMPOSE_FILES) restart
	@echo "$(GREEN)✓ Services restarted$(NC)"

clean: ## Stop services and remove volumes (DESTRUCTIVE!)
	@echo "$(RED)⚠ WARNING: This will delete all data in Docker volumes!$(NC)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "$(BLUE)Stopping services and removing volumes...$(NC)"; \
		docker compose $(COMPOSE_FILES) down -v; \
		echo "$(GREEN)✓ Services stopped and volumes removed$(NC)"; \
	else \
		echo "$(YELLOW)Cancelled$(NC)"; \
	fi

ps: ## Show running containers
	@docker compose $(COMPOSE_FILES) ps

health: ## Check health status of all services
	@echo "$(BLUE)Checking service health...$(NC)"
	@docker compose $(COMPOSE_FILES) ps --format "table {{.Service}}\t{{.Status}}\t{{.Ports}}"

# -----------------------------------------------------------------------------
# Logs
# -----------------------------------------------------------------------------
logs: ## Tail logs from all services
	@docker compose $(COMPOSE_FILES) logs -f

logs-admin: ## Tail logs from Admin service
	@docker compose $(COMPOSE_FILES) logs -f threesixty-admin

logs-discovery: ## Tail logs from Discovery service
	@docker compose $(COMPOSE_FILES) logs -f threesixty-discovery

logs-mongo: ## Tail logs from MongoDB
	@docker compose $(COMPOSE_FILES) logs -f mongo

logs-nginx: ## Tail logs from Nginx
	@docker compose $(COMPOSE_FILES) logs -f nginx

logs-ollama: ## Tail logs from Ollama
	@docker compose $(COMPOSE_FILES) logs -f ollama

logs-opensearch: ## Tail logs from OpenSearch
	@docker compose $(COMPOSE_FILES) logs -f opensearch

logs-scim: ## Tail logs from SCIM server
	@docker compose $(COMPOSE_FILES) logs -f scim-server

logs-rabbitmq: ## Tail logs from RabbitMQ
	@docker compose $(COMPOSE_FILES) logs -f rabbitmq

# -----------------------------------------------------------------------------
# Shell Access
# -----------------------------------------------------------------------------
exec-admin: ## Open shell in Admin container
	@docker exec -it threesixty-admin /bin/bash

exec-mongo: ## Open MongoDB shell
	@docker exec -it mongo mongosh

# -----------------------------------------------------------------------------
# Updates
# -----------------------------------------------------------------------------
pull: aws-login ## Pull latest images from ECR
	@echo "$(BLUE)Pulling latest images...$(NC)"
	@docker compose $(COMPOSE_FILES) pull
	@echo "$(GREEN)✓ Images updated$(NC)"

update: pull restart ## Pull latest images and restart services

rebuild: ## Rebuild and restart services
	@echo "$(BLUE)Rebuilding services...$(NC)"
	@docker compose $(COMPOSE_FILES) up -d --build --force-recreate
	@echo "$(GREEN)✓ Services rebuilt$(NC)"

# -----------------------------------------------------------------------------
# Monitoring Stack (Optional)
# -----------------------------------------------------------------------------
monitoring-start: ## Start Prometheus + Grafana monitoring stack
	@echo "$(BLUE)Starting monitoring stack...$(NC)"
	@docker compose $(MONITORING_COMPOSE) up -d
	@echo "$(GREEN)✓ Monitoring started$(NC)"
	@echo ""
	@echo "$(YELLOW)Access URLs:$(NC)"
	@echo "  Prometheus:  http://localhost:9090"
	@echo "  Grafana:     http://localhost:3001 (admin/admin)"
	@echo "  Node Exporter: http://localhost:9100/metrics"

monitoring-stop: ## Stop monitoring stack
	@echo "$(BLUE)Stopping monitoring stack...$(NC)"
	@docker compose $(MONITORING_COMPOSE) down
	@echo "$(GREEN)✓ Monitoring stopped$(NC)"

monitoring-logs: ## View monitoring stack logs
	@docker compose $(MONITORING_COMPOSE) logs -f

# -----------------------------------------------------------------------------
# Vault (Optional)
# -----------------------------------------------------------------------------
vault-start: ## Start HashiCorp Vault (dev mode)
	@echo "$(BLUE)Starting Vault...$(NC)"
	@docker compose $(VAULT_COMPOSE) up -d
	@echo "$(GREEN)✓ Vault started at http://localhost:8200$(NC)"
	@echo "$(YELLOW)⚠ Dev mode token: root$(NC)"

vault-stop: ## Stop Vault
	@echo "$(BLUE)Stopping Vault...$(NC)"
	@docker compose $(VAULT_COMPOSE) down
	@echo "$(GREEN)✓ Vault stopped$(NC)"

# -----------------------------------------------------------------------------
# Remote Agent (Optional)
# -----------------------------------------------------------------------------
oi-agent-start: ## Start OI Remote Agent
	@echo "$(BLUE)Starting OI Remote Agent...$(NC)"
	@if ! grep -q "REMOTE_AGENT_TOKEN=" .env || grep -q "REMOTE_AGENT_TOKEN=$$" .env; then \
		echo "$(RED)✗ REMOTE_AGENT_TOKEN not configured in .env$(NC)"; \
		echo "$(YELLOW)  1. Create remote agent in Admin UI$(NC)"; \
		echo "$(YELLOW)  2. Update .env with token and name$(NC)"; \
		exit 1; \
	fi
	@docker compose $(OI_AGENT_COMPOSE) up -d
	@echo "$(GREEN)✓ Remote Agent started$(NC)"

oi-agent-stop: ## Stop OI Remote Agent
	@echo "$(BLUE)Stopping OI Remote Agent...$(NC)"
	@docker compose $(OI_AGENT_COMPOSE) down
	@echo "$(GREEN)✓ Remote Agent stopped$(NC)"

# -----------------------------------------------------------------------------
# OpenSearch + Dashboards (Optional – preferred over Elasticsearch)
# -----------------------------------------------------------------------------
# OpenSearch is part of the core stack (docker-compose.yaml) and already
# starts with 'make start'. Use these targets to start/stop it independently.
# Ports: 9200 (API), 9300 (transport), 15601 (Dashboards UI).
opensearch-start: ## Start OpenSearch + Dashboards (preferred search engine)
	@echo "$(BLUE)Starting OpenSearch + Dashboards...$(NC)"
	@docker compose $(COMPOSE_FILES) up -d opensearch opensearch-dashboard
	@echo "$(GREEN)✓ OpenSearch + Dashboards started$(NC)"
	@echo ""
	@echo "$(YELLOW)Access URLs:$(NC)"
	@echo "  OpenSearch API:        http://localhost:9200"
	@echo "  OpenSearch Dashboards: http://localhost:15601"

opensearch-stop: ## Stop OpenSearch + Dashboards
	@echo "$(BLUE)Stopping OpenSearch + Dashboards...$(NC)"
	@docker compose $(COMPOSE_FILES) stop opensearch opensearch-dashboard
	@echo "$(GREEN)✓ OpenSearch + Dashboards stopped$(NC)"

opensearch-logs: ## View OpenSearch + Dashboards logs
	@docker compose $(COMPOSE_FILES) logs -f opensearch opensearch-dashboard

# -----------------------------------------------------------------------------
# Elasticsearch + Kibana (Optional – legacy, prefer opensearch-start instead)
# -----------------------------------------------------------------------------
# Elasticsearch is remapped to host ports 19200/19300 so it can run alongside
# OpenSearch (which owns 9200/9300) without a port bind conflict.
# Kibana remains on 5601 (no conflict with OpenSearch Dashboards on 15601).
elasticsearch-start: ## Start Elasticsearch + Kibana (legacy — use opensearch-start instead)
	@echo "$(YELLOW)⚠ Elasticsearch is a legacy option. Prefer 'make opensearch-start'.$(NC)"
	@echo "$(YELLOW)  Ports remapped to 19200/19300 to avoid clash with OpenSearch (9200/9300).$(NC)"
	@echo "$(BLUE)Starting Elasticsearch + Kibana...$(NC)"
	@docker compose $(ELASTICSEARCH_COMPOSE) up -d
	@echo "$(GREEN)✓ Elasticsearch + Kibana started$(NC)"
	@echo ""
	@echo "$(YELLOW)Access URLs:$(NC)"
	@echo "  Kibana:         http://localhost:5601"
	@echo "  Elasticsearch:  http://localhost:19200  (host-remapped from 9200)"

elasticsearch-stop: ## Stop Elasticsearch + Kibana
	@echo "$(BLUE)Stopping Elasticsearch + Kibana...$(NC)"
	@docker compose $(ELASTICSEARCH_COMPOSE) down
	@echo "$(GREEN)✓ Elasticsearch + Kibana stopped$(NC)"

elasticsearch-logs: ## View Elasticsearch + Kibana logs
	@docker compose $(ELASTICSEARCH_COMPOSE) logs -f

# -----------------------------------------------------------------------------
# Backup & Restore
# -----------------------------------------------------------------------------
backup: ## Backup MongoDB data
	@echo "$(BLUE)Backing up MongoDB...$(NC)"
	@mkdir -p backups
	@BACKUP="backup-$$(date +%Y%m%d-%H%M%S).archive"; \
	docker exec mongo mongodump --archive=/tmp/$$BACKUP && \
	docker cp mongo:/tmp/$$BACKUP ./backups/$$BACKUP; \
	echo "$(GREEN)✓ Backup completed: ./backups/$$BACKUP$(NC)"

restore: ## Restore MongoDB from latest backup
	@echo "$(BLUE)Restoring MongoDB from latest backup...$(NC)"
	@LATEST=$$(ls -t backups/*.archive 2>/dev/null | head -1); \
	if [ -z "$$LATEST" ]; then \
		echo "$(RED)✗ No backup files found in ./backups/$(NC)"; \
		exit 1; \
	fi; \
	echo "$(YELLOW)Restoring from: $$LATEST$(NC)"; \
	docker cp "$$LATEST" mongo:/tmp/restore.archive; \
	docker exec mongo mongorestore --archive=/tmp/restore.archive --drop; \
	echo "$(GREEN)✓ Restore completed$(NC)"

# -----------------------------------------------------------------------------
# Version Management
# -----------------------------------------------------------------------------
show-versions: ## Show current image versions from versions.env
	@echo "$(BLUE)===============================================================================$(NC)"
	@echo "$(GREEN)3Sixty Image Version Manifest$(NC)"
	@echo "$(BLUE)===============================================================================$(NC)"
	@echo ""
	@echo "$(YELLOW)Objective ECR images:$(NC)"
	@echo "  IMAGE_3SIXTY_ADMIN          = $(IMAGE_3SIXTY_ADMIN)"
	@echo "  IMAGE_3SIXTY_DISCOVERY      = $(IMAGE_3SIXTY_DISCOVERY)"
	@echo "  IMAGE_SCIM                  = $(IMAGE_SCIM)"
	@echo "  IMAGE_RAG                   = $(IMAGE_RAG)"
	@echo "  IMAGE_REMOTE_AGENT          = $(IMAGE_REMOTE_AGENT)"
	@echo ""
	@echo "$(YELLOW)Public images:$(NC)"
	@echo "  IMAGE_NGINX                 = $(IMAGE_NGINX)"
	@echo "  IMAGE_MONGO                 = $(IMAGE_MONGO)"
	@echo "  IMAGE_OPENSEARCH            = $(IMAGE_OPENSEARCH)"
	@echo "  IMAGE_OPENSEARCH_DASHBOARDS = $(IMAGE_OPENSEARCH_DASHBOARDS)"
	@echo "  IMAGE_RABBITMQ              = $(IMAGE_RABBITMQ)"
	@echo "  IMAGE_OLLAMA                = $(IMAGE_OLLAMA)"
	@echo ""
	@echo "$(YELLOW)Edit versions.env to update image versions.$(NC)"

# -----------------------------------------------------------------------------
# Validation & Security
# -----------------------------------------------------------------------------
validate: ## Validate Docker Compose configuration
	@echo "$(BLUE)Validating Docker Compose files...$(NC)"
	@docker compose $(COMPOSE_FILES) config > /dev/null
	@echo "$(GREEN)✓ Configuration valid$(NC)"

security-scan: ## Run security scan on running containers (requires Docker Scout)
	@echo "$(BLUE)Running security scan...$(NC)"
	@if ! docker scout version > /dev/null 2>&1; then \
		echo "$(YELLOW)⚠ Docker Scout not installed$(NC)"; \
		echo "$(YELLOW)  Install: docker scout install$(NC)"; \
		exit 1; \
	fi
	@docker scout cves

# -----------------------------------------------------------------------------
# Default Target
# -----------------------------------------------------------------------------
.DEFAULT_GOAL := help
