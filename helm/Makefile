#!/usr/bin/env make
# =============================================================================
# 3Sixty Deployment Makefile
# =============================================================================
# Automates Kubernetes deployment of the 3Sixty stack via Helm.
#
# USAGE:
#   make <target>
#
# QUICK START (standard kubectl access — Linux / macOS / Windows Git Bash):
#   1. make check-prerequisites   # Verify kubectl, helm, aws, az, openssl, jq are installed
#   2. make secrets-kubectl       # Create Kubernetes secrets (edit kubectl-create-secrets.sh first)
#   3. make deps                  # Download Helm subchart dependencies
#   4. make install               # Install the Helm release
#   5. make status                # Verify all pods are running
#
# QUICK START (Azure AKS without direct kubectl access):
#   1. make check-prerequisites   # Verify required tools
#   2. make aks-credentials       # Configure kubectl for your AKS cluster
#   3. make secrets-aks           # Create Kubernetes secrets via AKS invoke
#   4. make deps                  # Download Helm subchart dependencies
#   5. make install               # Install the Helm release
#   6. make status                # Verify all pods are running
#
# CONFIGURATION:
#   Override RELEASE, NAMESPACE, or VALUES_FILE from the command line:
#     make install RELEASE=myrelease NAMESPACE=myns VALUES_FILE=my-values.yaml
# =============================================================================

# Cross-platform shell: Git Bash on Windows, /bin/bash everywhere else.
# The .sh secrets scripts run through this shell on all platforms.
# Override BASH_PATH if Git is not installed in the default location on Windows.
ifeq ($(OS),Windows_NT)
    BASH_PATH ?= C:/Program Files/Git/usr/bin/bash.exe
    SHELL     := $(BASH_PATH)
else
    SHELL := /bin/bash
endif

SLEEP10 := sleep 10

# --- Configuration ------------------------------------------------------------
RELEASE       ?= threesixty-stack
NAMESPACE     ?= threesixty
CHART_DIR     ?= .
VALUES_FILE   ?= values-production.yaml
AKS_RG        ?= $(error AKS_RG is required — set with: make <target> AKS_RG=<resource-group>)
AKS_CLUSTER   ?= $(error AKS_CLUSTER is required — set with: make <target> AKS_CLUSTER=<cluster-name>)
ECR_REGISTRY  ?= $(error ECR_REGISTRY is required — set with: make ecr-login ECR_REGISTRY=<account-id>.dkr.ecr.<region>.amazonaws.com)
AWS_REGION    ?= ap-southeast-2

# --- Colours ------------------------------------------------------------------
GREEN  := \033[0;32m
YELLOW := \033[0;33m
CYAN   := \033[0;36m
RESET  := \033[0m

.DEFAULT_GOAL := help

.PHONY: help check-prerequisites aks-credentials deps \
        secrets-kubectl secrets-aks verify-secrets ecr-login \
        install install-metallb upgrade uninstall reinstall \
        status pods logs events \
        rollback history \
        lint template validate \
        clean purge

# =============================================================================
# HELP
# =============================================================================

help: ## Show this help message
	@echo ""
	@printf "$(CYAN)3Sixty Deployment Makefile$(RESET)\n"
	@echo  "Usage: make [target] [KEY=VALUE ...]"
	@echo ""
	@printf "$(YELLOW)Variables (with defaults):$(RESET)\n"
	@echo  "  RELEASE=$(RELEASE)"
	@echo  "  NAMESPACE=$(NAMESPACE)"
	@echo  "  CHART_DIR=$(CHART_DIR)"
	@echo  "  VALUES_FILE=$(VALUES_FILE)"
	@echo  "  AKS_RG=<required for AKS targets>"
	@echo  "  AKS_CLUSTER=<required for AKS targets>"
	@echo  "  ECR_REGISTRY=<account-id>.dkr.ecr.<region>.amazonaws.com (required for ecr-login)"
	@echo  "  AWS_REGION=$(AWS_REGION)"
	@echo  "  BASH_PATH=<path>  (Windows only — override if Git is not in the default location)"
	@echo ""
	@printf "$(YELLOW)Targets:$(RESET)\n"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(RESET) %s\n", $$1, $$2}'
	@echo ""

# =============================================================================
# PREREQUISITES
# =============================================================================

check-prerequisites: ## Check required tools are installed (kubectl, helm, aws, az, openssl, jq)
	@echo ""
	@printf "$(CYAN)[CHECK] Checking required tools...$(RESET)\n"
	@MISSING=0; \
	for tool in kubectl helm aws az openssl jq; do \
		if command -v $$tool >/dev/null 2>&1; then \
			printf "  $(GREEN)[OK]$(RESET)      $$tool\n"; \
		else \
			printf "  $(YELLOW)[MISSING]$(RESET) $$tool\n"; \
			MISSING=1; \
		fi; \
	done; \
	if [ $$MISSING -eq 1 ]; then \
		echo ""; \
		printf "$(YELLOW)Install missing tools:$(RESET)\n"; \
		printf "  macOS:   brew install kubectl helm awscli azure-cli openssl jq\n"; \
		printf "  Ubuntu:  sudo apt-get install -y kubectl jq openssl\n"; \
		printf "           curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash\n"; \
		printf "           (az and aws: see https://learn.microsoft.com/cli/azure/install-azure-cli and https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)\n"; \
		printf "  Windows: winget install Kubernetes.kubectl Helm.Helm Amazon.AWSCLI Microsoft.AzureCLI ShiningLight.OpenSSL jqlang.jq\n"; \
	else \
		printf "$(GREEN)[OK] All required tools found.$(RESET)\n"; \
	fi

aks-credentials: ## Configure kubectl for AKS (requires AKS_RG and AKS_CLUSTER)
	@echo ""
	@printf "$(CYAN)[AKS] Fetching AKS credentials for cluster '$(AKS_CLUSTER)' in '$(AKS_RG)'...$(RESET)\n"
	az aks get-credentials --resource-group $(AKS_RG) --name $(AKS_CLUSTER) --overwrite-existing
	kubectl config current-context
	@printf "$(GREEN)[OK] kubectl configured for AKS cluster.$(RESET)\n"

# =============================================================================
# SECRETS
# =============================================================================

secrets-kubectl: ## Create Kubernetes secrets via kubectl (edit kubectl-create-secrets.sh first)
	@echo ""
	@printf "$(CYAN)[SECRETS] Creating Kubernetes secrets via kubectl...$(RESET)\n"
	@if [ ! -f kubectl-create-secrets.sh ]; then \
		cp kubectl-create-secrets.sh.example kubectl-create-secrets.sh; \
		printf "$(YELLOW)[SETUP] Copied kubectl-create-secrets.sh.example → kubectl-create-secrets.sh$(RESET)\n"; \
		printf "$(YELLOW)        Edit kubectl-create-secrets.sh and set your credentials, then re-run.$(RESET)\n"; \
		exit 1; \
	fi
	bash ./kubectl-create-secrets.sh
	@printf "$(GREEN)[OK] Secrets created.$(RESET)\n"

secrets-aks: ## Create Kubernetes secrets via AKS invoke (requires AKS_RG and AKS_CLUSTER)
	@echo ""
	@printf "$(CYAN)[SECRETS] Creating Kubernetes secrets via AKS invoke...$(RESET)\n"
	@if [ ! -f aks-create-secrets.sh ]; then \
		cp aks-create-secrets.sh.example aks-create-secrets.sh; \
		printf "$(YELLOW)[SETUP] Copied aks-create-secrets.sh.example → aks-create-secrets.sh$(RESET)\n"; \
		printf "$(YELLOW)        Edit aks-create-secrets.sh and set your credentials, then re-run.$(RESET)\n"; \
		exit 1; \
	fi
	bash ./aks-create-secrets.sh \
		--resource-group $(AKS_RG) \
		--cluster-name $(AKS_CLUSTER) \
		--namespace $(NAMESPACE)
	@printf "$(GREEN)[OK] Secrets created.$(RESET)\n"

ecr-login: ## Refresh the ECR image pull secret (expires every 12 h — re-run to rotate)
	@echo ""
	@printf "$(CYAN)[ECR] Logging in to $(ECR_REGISTRY) (region: $(AWS_REGION))...$(RESET)\n"
	@ECR_TOKEN=$$(aws ecr get-login-password --region $(AWS_REGION)) && \
		kubectl create secret docker-registry ecr-registry-secret \
			--docker-server=$(ECR_REGISTRY) \
			--docker-username=AWS \
			--docker-password=$$ECR_TOKEN \
			--namespace $(NAMESPACE) \
			--dry-run=client -o yaml | kubectl apply -f -
	@printf "$(GREEN)[OK] ecr-registry-secret created/updated in namespace '$(NAMESPACE)'.$(RESET)\n"
	@printf "$(YELLOW)NOTE: ECR tokens expire after 12 hours — run 'make ecr-login' again to refresh.$(RESET)\n"

verify-secrets: ## List all secrets in the namespace and verify required secrets exist
	@echo ""
	@printf "$(CYAN)[VERIFY] Checking secrets in namespace '$(NAMESPACE)'...$(RESET)\n"
	@kubectl get secrets -n $(NAMESPACE) --no-headers 2>/dev/null || \
		(printf "$(YELLOW)[WARN] Namespace '$(NAMESPACE)' not found or no secrets. Run secrets-kubectl or secrets-aks first.$(RESET)\n" && exit 1)
	@echo ""
	@printf "$(CYAN)Checking required secrets:$(RESET)\n"
	@for secret in \
		ecr-registry-secret \
		traefik-tls \
		$(RELEASE)-rabbitmq-secret \
		$(RELEASE)-mongo-init-secret \
		$(RELEASE)-opensearch-admin-secret \
		$(RELEASE)-hybridsearch-oirag-secret \
		$(RELEASE)-hybridsearch-remoteagent-secret; do \
		if kubectl get secret $$secret -n $(NAMESPACE) &>/dev/null; then \
			printf "  $(GREEN)[OK]$(RESET) $$secret\n"; \
		else \
			printf "  $(YELLOW)[MISSING]$(RESET) $$secret\n"; \
		fi; \
	done

# =============================================================================
# HELM LIFECYCLE
# =============================================================================

deps: ## Download / update Helm subchart dependencies
	@echo ""
	@printf "$(CYAN)[DEPS] Updating Helm dependencies...$(RESET)\n"
	helm dependency update $(CHART_DIR)
	@printf "$(GREEN)[OK] Dependencies updated.$(RESET)\n"

install: ## Install the Helm release (fails if already exists — use upgrade instead)
	@echo ""
	@printf "$(CYAN)[INSTALL] Installing release '$(RELEASE)' in namespace '$(NAMESPACE)'...$(RESET)\n"
	@test -f $(VALUES_FILE) || (printf "$(YELLOW)[ERROR] Values file '$(VALUES_FILE)' not found.\nCopy and fill in: cp values-production.yaml.template values-production.yaml$(RESET)\n" && exit 1)
	helm install $(RELEASE) $(CHART_DIR) \
		--namespace $(NAMESPACE) \
		--create-namespace \
		--values $(VALUES_FILE) \
		--timeout 10m \
		--wait
	@printf "$(GREEN)[OK] Release '$(RELEASE)' installed.$(RESET)\n"
	@$(MAKE) status

upgrade: ## Upgrade the Helm release (also installs if not present)
	@echo ""
	@printf "$(CYAN)[UPGRADE] Upgrading release '$(RELEASE)' in namespace '$(NAMESPACE)'...$(RESET)\n"
	@test -f $(VALUES_FILE) || (printf "$(YELLOW)[ERROR] Values file '$(VALUES_FILE)' not found.$(RESET)\n" && exit 1)
	helm upgrade --install $(RELEASE) $(CHART_DIR) \
		--namespace $(NAMESPACE) \
		--create-namespace \
		--values $(VALUES_FILE) \
		--timeout 10m \
		--wait \
		--force-conflicts
	@printf "$(GREEN)[OK] Release '$(RELEASE)' upgraded.$(RESET)\n"
	@$(MAKE) status

uninstall: ## Uninstall the Helm release (PVCs are kept — see 'purge' to also delete them)
	@echo ""
	@printf "$(YELLOW)[UNINSTALL] Removing release '$(RELEASE)' from namespace '$(NAMESPACE)'...$(RESET)\n"
	@printf "$(YELLOW)NOTE: PVCs will be retained (helm.sh/resource-policy: keep). Run 'make purge' to also delete PVCs.$(RESET)\n"
	helm uninstall $(RELEASE) --namespace $(NAMESPACE)
	@printf "$(GREEN)[OK] Release uninstalled. PVCs retained.$(RESET)\n"

reinstall: uninstall deps install ## Uninstall then reinstall (PVCs retained — data preserved)

# =============================================================================
# METALLB (bare-metal / on-premises only)
# =============================================================================

install-metallb: ## Install MetalLB via Helm then apply metallb-config.yaml (bare-metal only — NOT for AKS/EKS/GKE)
	@echo ""
	@printf "$(YELLOW)NOTE: MetalLB is for bare-metal / on-premises clusters only.$(RESET)\n"
	@printf "$(YELLOW)      Do NOT run this on AKS, EKS, or GKE — they provide native load balancing.$(RESET)\n"
	@printf "$(YELLOW)      Edit metallb-config.yaml and set your IP address range before continuing.$(RESET)\n"
	@echo ""
	@printf "$(CYAN)[METALLB] Adding MetalLB Helm repository...$(RESET)\n"
	helm repo add metallb https://metallb.github.io/metallb
	helm repo update
	@printf "$(CYAN)[METALLB] Installing MetalLB into namespace 'metallb-system'...$(RESET)\n"
	helm install metallb metallb/metallb \
		--namespace metallb-system \
		--create-namespace
	@printf "$(CYAN)[METALLB] Waiting for MetalLB controller to be ready...$(RESET)\n"
	kubectl rollout status deployment/metallb-controller -n metallb-system --timeout=120s
	@printf "$(CYAN)[METALLB] Applying IP address pool configuration...$(RESET)\n"
	kubectl apply -f metallb-config.yaml
	@printf "$(GREEN)[OK] MetalLB installed and configured.$(RESET)\n"

rollback: ## Roll back to the previous Helm release revision
	@echo ""
	@printf "$(CYAN)[ROLLBACK] Rolling back release '$(RELEASE)'...$(RESET)\n"
	helm rollback $(RELEASE) --namespace $(NAMESPACE) --wait
	@printf "$(GREEN)[OK] Rollback complete.$(RESET)\n"

# =============================================================================
# OBSERVABILITY
# =============================================================================

status: ## Show Helm release status and all pod states
	@echo ""
	@printf "$(CYAN)[STATUS] Helm release:$(RESET)\n"
	@helm status $(RELEASE) --namespace $(NAMESPACE) 2>/dev/null || \
		printf "$(YELLOW)Release '$(RELEASE)' not found in namespace '$(NAMESPACE)'.$(RESET)\n"
	@echo ""
	@printf "$(CYAN)[STATUS] Pods in namespace '$(NAMESPACE)':$(RESET)\n"
	@kubectl get pods -n $(NAMESPACE) -o wide 2>/dev/null || true
	@echo ""
	@printf "$(CYAN)[STATUS] Services:$(RESET)\n"
	@kubectl get services -n $(NAMESPACE) 2>/dev/null || true

pods: ## Watch pod status in real time (Ctrl+C to exit)
	kubectl get pods -n $(NAMESPACE) --watch

logs: ## Tail logs for a specific deployment (usage: make logs DEPLOY=admin)
ifndef DEPLOY
	@printf "$(YELLOW)Usage: make logs DEPLOY=<name>$(RESET)\n"
	@printf "Available deployments:\n"
	@kubectl get deployments -n $(NAMESPACE) --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null || true
else
	kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/component=$(DEPLOY) -f --tail=100
endif

events: ## Show recent Kubernetes events in the namespace (useful for debugging)
	kubectl get events -n $(NAMESPACE) --sort-by='.lastTimestamp' | tail -40

history: ## Show Helm release history
	helm history $(RELEASE) --namespace $(NAMESPACE)

# =============================================================================
# VALIDATION
# =============================================================================

lint: ## Lint the Helm chart for errors and best-practice issues
	@echo ""
	@printf "$(CYAN)[LINT] Linting chart...$(RESET)\n"
	helm lint $(CHART_DIR) --values $(VALUES_FILE)
	@printf "$(GREEN)[OK] Lint passed.$(RESET)\n"

template: ## Render Helm templates locally (dry-run — does not install)
	@echo ""
	@printf "$(CYAN)[TEMPLATE] Rendering templates for release '$(RELEASE)'...$(RESET)\n"
	helm template $(RELEASE) $(CHART_DIR) \
		--namespace $(NAMESPACE) \
		--values $(VALUES_FILE)

validate: lint template ## Run lint then render templates (full dry-run validation)

# =============================================================================
# CLEANUP
# =============================================================================

clean: ## Remove downloaded chart dependencies (charts/ tarballs)
	@echo ""
	@printf "$(CYAN)[CLEAN] Removing downloaded chart dependencies...$(RESET)\n"
	@rm -f $(CHART_DIR)/charts/*.tgz
	@printf "$(GREEN)[OK] Cleaned chart tarballs.$(RESET)\n"

purge: ## DESTRUCTIVE: Uninstall release AND delete all PVCs (all data lost)
	@echo ""
	@printf "$(YELLOW)WARNING: This will delete ALL PVCs and their data in namespace '$(NAMESPACE)'.$(RESET)\n"
	@printf "$(YELLOW)This cannot be undone. Press Ctrl+C within 10 seconds to cancel...$(RESET)\n"
	@$(SLEEP10)
	@helm uninstall $(RELEASE) --namespace $(NAMESPACE) || true
	@kubectl delete pvc --all -n $(NAMESPACE) || true
	@printf "$(GREEN)[OK] Release uninstalled and all PVCs deleted.$(RESET)\n"
