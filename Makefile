# Wazuh Deployment Makefile
# Common operations for deploying and managing Wazuh infrastructure
#
# Usage: make <target>
# Run 'make help' to see all available targets

.PHONY: help setup setup-tui setup-docker deploy deploy-check deploy-bootstrap deploy-indexer deploy-manager \
        deploy-dashboard deploy-agent health backup restore upgrade upgrade-check \
        check check-files check-vault status unlock vault-view vault-edit vault-rotate vault-rekey certs-check \
        certs-rotate certs-renew clean clean-all monitoring test lint deploy-rules threat-intel bats \
        check-docker docker-setup setup-hooks

# Default target
.DEFAULT_GOAL := help

# Colors for output
CYAN := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
RESET := \033[0m

#═══════════════════════════════════════════════════════════════════════════════
# Help
#═══════════════════════════════════════════════════════════════════════════════

help: ## Show this help message
	@echo "$(CYAN)Wazuh Deployment - Available Commands$(RESET)"
	@echo ""
	@echo "$(GREEN)Setup:$(RESET)"
	@grep -E '^(setup|setup-tui|check|check-vault):.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  $(CYAN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Deployment:$(RESET)"
	@grep -E '^deploy[^:]*:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  $(CYAN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Operations:$(RESET)"
	@grep -E '^(health|status|backup|restore|upgrade|upgrade-check|unlock|monitoring|threat-intel):.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  $(CYAN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Security:$(RESET)"
	@grep -E '^(vault-|certs-)[^:]*:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  $(CYAN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Docker:$(RESET)"
	@grep -E '^(check-docker|docker-setup):.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  $(CYAN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Development:$(RESET)"
	@grep -E '^(test|bats|lint|clean|clean-all):.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  $(CYAN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Examples:$(RESET)"
	@echo "  make setup               # Run interactive CLI setup"
	@echo "  make deploy-bootstrap    # First-time deployment with bootstrap"
	@echo "  make deploy              # Regular deployment"
	@echo "  make status              # Quick health check"
	@echo "  make backup              # Create backup of Wazuh data"
	@echo "  make vault-view          # View vault credentials"
	@echo "  make certs-check         # Check certificate expiration"
	@echo "  make upgrade-check       # Check available upgrades"

#═══════════════════════════════════════════════════════════════════════════════
# Setup
#═══════════════════════════════════════════════════════════════════════════════

setup: ## Run interactive CLI setup wizard
	@./setup.sh

setup-tui: ## Run beautiful TUI setup (requires gum)
	@./setup-tui.sh

setup-docker: ## Run CLI setup with docker container environment defaults
	@echo "Running setup with Docker container environment defaults..."
	@INDEXER_NODES="172.18.0.2" MANAGER_NODES="172.18.0.3" DASHBOARD_NODES="172.18.0.4" \
		AGENT_NODES="172.18.0.5" DEPLOY_AGENTS="true" \
		CUSTOM_PASSWORDS="true" API_USER="wazuh" API_PASSWORD="WazuhAPI456!" \
		INDEXER_ADMIN_PASSWORD="WazuhAdmin12345!" ENROLLMENT_PASSWORD="WazuhEnroll789!" \
		FILEBEAT_PASSWORD="WazuhFilebeat000!" \
		GENERATE_SSH_KEY="false" SAME_SSH_CREDS="true" SSH_USER="wazuh-deploy" \
		USE_SELF_SIGNED_CERTS="true" \
		./setup.sh --profile docker

check-vault: ## Validate vault.yml is encrypted
	@if [ -f group_vars/all/vault.yml ]; then \
		if head -1 group_vars/all/vault.yml | grep -q '^\$$ANSIBLE_VAULT'; then \
			echo "$(GREEN)✓$(RESET) Vault: group_vars/all/vault.yml (encrypted)"; \
		else \
			echo "$(RED)✗$(RESET) Vault: group_vars/all/vault.yml is NOT encrypted!"; \
			echo "  Run: ansible-vault encrypt group_vars/all/vault.yml"; \
			exit 1; \
		fi; \
	else \
		echo "$(YELLOW)⚠$(RESET) Vault not configured"; \
	fi

setup-hooks: ## Configure git hooks
	@git config core.hooksPath .githooks 2>/dev/null || true
	@echo "$(GREEN)✓$(RESET) Git hooks configured: .githooks/"

check: setup-hooks ## Validate prerequisites and configuration
	@echo "$(CYAN)Checking prerequisites...$(RESET)"
	@command -v ansible >/dev/null 2>&1 || { echo "$(RED)Error: ansible not found$(RESET)"; exit 1; }
	@command -v ansible-playbook >/dev/null 2>&1 || { echo "$(RED)Error: ansible-playbook not found$(RESET)"; exit 1; }
	@echo "$(GREEN)✓$(RESET) Ansible: $$(ansible --version | head -1)"
	@if [ -f inventory/hosts.yml ]; then \
		echo "$(GREEN)✓$(RESET) Inventory: inventory/hosts.yml"; \
	else \
		echo "$(YELLOW)⚠$(RESET) Inventory not found - run 'make setup' first"; \
	fi
	@if [ -f ~/.config/wazuh-deployment/.vault_password ]; then \
		echo "$(GREEN)✓$(RESET) Vault password: ~/.config/wazuh-deployment/.vault_password"; \
	else \
		echo "$(YELLOW)⚠$(RESET) Vault password not found"; \
	fi
	@if [ -f group_vars/all/vault.yml ]; then \
		if head -1 group_vars/all/vault.yml | grep -q '^\$$ANSIBLE_VAULT'; then \
			echo "$(GREEN)✓$(RESET) Vault: group_vars/all/vault.yml (encrypted)"; \
		else \
			echo "$(RED)✗$(RESET) Vault: group_vars/all/vault.yml is NOT encrypted!"; \
			echo "  Run: ansible-vault encrypt group_vars/all/vault.yml --vault-password-file ~/.config/wazuh-deployment/.vault_password"; \
			exit 1; \
		fi; \
	else \
		echo "$(YELLOW)⚠$(RESET) Vault not configured"; \
	fi
	@echo ""
	@echo "$(CYAN)Checking connectivity...$(RESET)"
	@ansible all -m ping --one-line 2>/dev/null || echo "$(YELLOW)⚠$(RESET) Could not reach all hosts"

#═══════════════════════════════════════════════════════════════════════════════
# Deployment
#═══════════════════════════════════════════════════════════════════════════════

deploy: check-files ## Deploy all Wazuh components
	@echo "$(CYAN)Deploying Wazuh stack...$(RESET)"
	@read -p "$(YELLOW)Continue with deployment? [y/N]$(RESET) " confirm && [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ] || { echo "Aborted."; exit 1; }
	ansible-playbook site.yml --vault-password-file ~/.config/wazuh-deployment/.vault_password

deploy-bootstrap: check-files ## First-time deployment (bootstrap + all components)
	@echo "$(CYAN)Running bootstrap + full deployment...$(RESET)"
	ansible-playbook site.yml --tags bootstrap,all --ask-pass --vault-password-file ~/.config/wazuh-deployment/.vault_password

deploy-check: check-files ## Dry-run deployment (no changes)
	@echo "$(CYAN)Running deployment in check mode...$(RESET)"
	ansible-playbook site.yml --check --diff --vault-password-file ~/.config/wazuh-deployment/.vault_password

deploy-indexer: check-files ## Deploy only indexer nodes
	@echo "$(CYAN)Deploying indexers...$(RESET)"
	ansible-playbook site.yml --tags indexer --vault-password-file ~/.config/wazuh-deployment/.vault_password

deploy-manager: check-files ## Deploy only manager nodes
	@echo "$(CYAN)Deploying managers...$(RESET)"
	ansible-playbook site.yml --tags manager --vault-password-file ~/.config/wazuh-deployment/.vault_password

deploy-dashboard: check-files ## Deploy only dashboard nodes
	@echo "$(CYAN)Deploying dashboards...$(RESET)"
	ansible-playbook site.yml --tags dashboard --vault-password-file ~/.config/wazuh-deployment/.vault_password

deploy-agent: check-files ## Deploy agents to monitored hosts
	@echo "$(CYAN)Deploying agents...$(RESET)"
	ansible-playbook site.yml --tags agent --vault-password-file ~/.config/wazuh-deployment/.vault_password

check-files:
	@if [ ! -f inventory/hosts.yml ]; then \
		echo "$(RED)Error: inventory/hosts.yml not found.$(RESET)"; \
		echo "  Run 'make setup' or 'make setup-docker' first."; \
		exit 1; \
	fi
	@if [ ! -f group_vars/all/main.yml ]; then \
		echo "$(RED)Error: group_vars/all/main.yml not found.$(RESET)"; \
		echo "  Run 'make setup' or 'make setup-docker' first."; \
		exit 1; \
	fi
	@if [ ! -f group_vars/all/vault.yml ]; then \
		echo "$(RED)Error: group_vars/all/vault.yml not found.$(RESET)"; \
		echo "  Run 'make setup' or 'make setup-docker' first."; \
		exit 1; \
	fi
	@echo "$(GREEN)✓$(RESET) Config files found"

#═══════════════════════════════════════════════════════════════════════════════
# Operations
#═══════════════════════════════════════════════════════════════════════════════

health: ## Run comprehensive health check
	@echo "$(CYAN)Running health check...$(RESET)"
	ansible-playbook playbooks/health-check.yml --vault-password-file ~/.config/wazuh-deployment/.vault_password

status: ## Quick status check of all services
	@if [ -f scripts/status.sh ]; then \
		./scripts/status.sh; \
	else \
		echo "$(CYAN)Checking service status...$(RESET)"; \
		ansible all -m shell -a "systemctl is-active wazuh-indexer wazuh-manager wazuh-dashboard wazuh-agent 2>/dev/null || true" --one-line; \
	fi

backup: ## Create backup of Wazuh data
	@echo "$(CYAN)Creating backup...$(RESET)"
	ansible-playbook playbooks/backup.yml --vault-password-file ~/.config/wazuh-deployment/.vault_password

restore: ## Restore from backup (requires BACKUP_ID)
	@if [ -z "$(BACKUP_ID)" ]; then \
		echo "$(RED)Error: BACKUP_ID required$(RESET)"; \
		echo "Usage: make restore BACKUP_ID=20260101T120000"; \
		exit 1; \
	fi
	@echo "$(CYAN)Restoring from backup $(BACKUP_ID)...$(RESET)"
	ansible-playbook playbooks/restore.yml -e "restore_from=$(BACKUP_ID)" --vault-password-file ~/.config/wazuh-deployment/.vault_password

upgrade: ## Upgrade Wazuh to version in group_vars
	@echo "$(CYAN)Running upgrade...$(RESET)"
	ansible-playbook playbooks/upgrade.yml --vault-password-file ~/.config/wazuh-deployment/.vault_password

upgrade-check: ## Check available upgrades (no changes)
	@echo "$(CYAN)Checking for available upgrades...$(RESET)"
	ansible-playbook playbooks/upgrade.yml --tags check --vault-password-file ~/.config/wazuh-deployment/.vault_password

unlock: ## Unlock deployment user for new deployment
	@echo "$(CYAN)Unlocking deployment user...$(RESET)"
	ansible-playbook unlock-deploy-user.yml --vault-password-file ~/.config/wazuh-deployment/.vault_password

monitoring: ## Enable Prometheus monitoring exporters
	@echo "$(CYAN)Deploying Prometheus exporters...$(RESET)"
	ansible-playbook site.yml --tags monitoring -e wazuh_monitoring_enabled=true --vault-password-file ~/.config/wazuh-deployment/.vault_password

deploy-rules: ## Deploy only custom rules, decoders, and CDB lists
	@echo "$(CYAN)Deploying custom rules and decoders...$(RESET)"
	ansible-playbook site.yml --tags manager -e wazuh_custom_content_enabled=true --vault-password-file ~/.config/wazuh-deployment/.vault_password

threat-intel: ## Update threat intelligence feeds (IPs, domains, hashes)
	@echo "$(CYAN)Updating threat intelligence feeds...$(RESET)"
	@./scripts/update-threat-intel.sh
	@echo ""
	@echo "$(GREEN)Feeds updated.$(RESET) Deploy with: make deploy-rules"

#═══════════════════════════════════════════════════════════════════════════════
# Security
#═══════════════════════════════════════════════════════════════════════════════

vault-view: ## View vault credentials
	@./scripts/manage-vault.sh view

vault-edit: ## Edit vault credentials
	@./scripts/manage-vault.sh edit

vault-rotate: ## Rotate all passwords
	@echo "$(CYAN)Rotating credentials...$(RESET)"
	@if [ -f playbooks/rotate-credentials.yml ]; then \
		ansible-playbook playbooks/rotate-credentials.yml --vault-password-file ~/.config/wazuh-deployment/.vault_password; \
	else \
		./scripts/manage-vault.sh rotate; \
	fi

vault-rekey: ## Change vault encryption password
	@./scripts/manage-vault.sh rekey

certs-check: ## Check certificate expiration
	@echo "$(CYAN)Checking certificate expiration...$(RESET)"
	ansible-playbook playbooks/certificate-management.yml --tags check-expiry --vault-password-file ~/.config/wazuh-deployment/.vault_password

certs-rotate: ## Rotate all certificates
	@echo "$(CYAN)Rotating certificates...$(RESET)"
	ansible-playbook playbooks/certificate-management.yml --tags rotate --vault-password-file ~/.config/wazuh-deployment/.vault_password

certs-renew: ## Renew expiring certificates
	@echo "$(CYAN)Renewing expiring certificates...$(RESET)"
	ansible-playbook playbooks/certificate-management.yml --tags renew --vault-password-file ~/.config/wazuh-deployment/.vault_password

#═══════════════════════════════════════════════════════════════════════════════
# Docker
#═══════════════════════════════════════════════════════════════════════════════

check-docker: ## Check Docker prerequisites
	@echo "$(CYAN)Checking Docker prerequisites...$(RESET)"
	@command -v docker >/dev/null 2>&1 || { echo "$(RED)Error: docker not found$(RESET)"; exit 1; }
	@command -v yq >/dev/null 2>&1 || { echo "$(RED)Error: yq not found$(RESET)"; exit 1; }
	@echo "$(GREEN)✓$(RESET) Docker: $$(docker --version)"
	@echo "$(GREEN)✓$(RESET) yq: $$(yq --version 2>&1 | head -1)"
	@if [ -f group_vars/all/vault.yml ]; then \
		echo "$(GREEN)✓$(RESET) Vault: group_vars/all/vault.yml"; \
	else \
		echo "$(YELLOW)⚠$(RESET) Vault not found - run 'make setup' first"; \
		exit 1; \
	fi

docker-setup: check-docker ## Full Docker environment (containers + deploy)
	@set -e; \
	echo "$(CYAN)══════════════════════════════════════════════$(RESET)"; \
	echo "$(CYAN)  Wazuh Docker Setup$(RESET)"; \
	echo "$(CYAN)══════════════════════════════════════════════$(RESET)"; \
	echo ""; \
	echo "Select deployment type:"; \
	echo "  1) Single-machine (Docker Compose)"; \
	echo "  2) Distributed (Docker Swarm)"; \
	read -p "Choice [1]: " mode; \
	mode=$${mode:-1}; \
	echo ""; \
	NET_NAME="wazuh-test_wazuh-net"; \
	if [ "$$mode" = "2" ]; then \
		echo "$(CYAN)Distributed mode: Deploying Swarm stack...$(RESET)"; \
		docker stack deploy -c docker-compose.yml wazuh; \
		echo "$(YELLOW)Waiting for Swarm services...$(RESET)"; \
		sleep 15; \
		NET_NAME="wazuh_wazuh-net"; \
	else \
		echo "$(CYAN)Single-machine mode: Starting containers...$(RESET)"; \
		docker compose up -d; \
		echo "$(YELLOW)Waiting for containers...$(RESET)"; \
		sleep 5; \
	fi; \
	echo ""; \
	echo "$(CYAN)Detecting container IPs...$(RESET)"; \
	INDEXER_IP=$$(docker inspect indexer-1 --format '{{(index .NetworkSettings.Networks "'$$NET_NAME'").IPAddress}}' 2>/dev/null || echo ""); \
	MANAGER_IP=$$(docker inspect manager-1 --format '{{(index .NetworkSettings.Networks "'$$NET_NAME'").IPAddress}}' 2>/dev/null || echo ""); \
	DASHBOARD_IP=$$(docker inspect dashboard-1 --format '{{(index .NetworkSettings.Networks "'$$NET_NAME'").IPAddress}}' 2>/dev/null || echo ""); \
	AGENT_IP=$$(docker inspect agent-1 --format '{{(index .NetworkSettings.Networks "'$$NET_NAME'").IPAddress}}' 2>/dev/null || echo ""); \
	if [ -z "$$INDEXER_IP" ]; then \
		echo "$(RED)Error: Could not detect container IPs. Are containers running?$(RESET)"; \
		exit 1; \
	fi; \
	echo "  indexer-1:    $$INDEXER_IP"; \
	echo "  manager-1:    $$MANAGER_IP"; \
	echo "  dashboard-1:  $$DASHBOARD_IP"; \
	echo "  agent-1:      $$AGENT_IP"; \
	echo ""; \
	echo "$(CYAN)Generating configuration with Docker IPs...$(RESET)"; \
	INDEXER_NODES="$$INDEXER_IP" \
	MANAGER_NODES="$$MANAGER_IP" \
	DASHBOARD_NODES="$$DASHBOARD_IP" \
	AGENT_NODES="$$AGENT_IP" \
	DEPLOY_AGENTS="true" \
	ENVIRONMENT="development" \
	CUSTOM_PASSWORDS="false" \
	USE_SELF_SIGNED_CERTS="true" \
	GENERATE_SSH_KEY="true" \
	ANSIBLE_USER="wazuh-deploy" \
	SAME_SSH_CREDS="true" \
	WAZUH_VERSION="${WAZUH_VERSION:-4.14.5}" \
	./setup.sh --profile docker --quiet; \
	echo ""; \
	echo "$(CYAN)Bootstrapping containers (SSH + deploy user)...$(RESET)"; \
	ansible-playbook -i inventory/docker-hosts.yml docker-bootstrap.yml --vault-password-file ~/.config/wazuh-deployment/.vault_password; \
	echo ""; \
	echo "$(CYAN)Deploying Wazuh stack...$(RESET)"; \
	ansible-playbook -i inventory/docker-hosts.yml site.yml --vault-password-file ~/.config/wazuh-deployment/.vault_password; \
	echo ""; \
	echo "$(GREEN)══════════════════════════════════════════════$(RESET)"; \
	echo "$(GREEN)  Wazuh Docker deployment complete!$(RESET)"; \
	echo "$(GREEN)══════════════════════════════════════════════$(RESET)"; \
	echo "  Dashboard: https://localhost:443"; \
	echo "  Username: admin"; \
	echo "  Password: (see vault output)"

#═══════════════════════════════════════════════════════════════════════════════
# Development
#═══════════════════════════════════════════════════════════════════════════════

test: bats ## Run all tests (BATS shell tests + Ansible syntax check + lint)
	@echo "$(CYAN)Running Ansible syntax check...$(RESET)"
	ansible-playbook site.yml --syntax-check
	@echo "$(CYAN)Running Ansible lint...$(RESET)"
	@if command -v ansible-lint >/dev/null 2>&1; then \
		ansible-lint site.yml roles/; \
	else \
		echo "$(YELLOW)⚠$(RESET) ansible-lint not installed, skipping"; \
	fi

bats: ## Run BATS unit tests for shell libraries
	@echo "$(CYAN)Running BATS tests...$(RESET)"
	@if command -v bats >/dev/null 2>&1; then \
		bats tests/lib/; \
	else \
		echo "$(RED)Error: bats not installed$(RESET)"; \
		echo "  Ubuntu/Debian: sudo apt-get install bats"; \
		echo "  macOS:         brew install bats-core"; \
		echo "  Manual:        https://github.com/bats-core/bats-core"; \
		exit 1; \
	fi

lint: ## Run ansible-lint on all playbooks
	@echo "$(CYAN)Linting playbooks...$(RESET)"
	@if command -v ansible-lint >/dev/null 2>&1; then \
		ansible-lint; \
	else \
		echo "$(RED)Error: ansible-lint not installed$(RESET)"; \
		echo "Install with: pip install ansible-lint"; \
		exit 1; \
	fi

clean: ## Remove generated files (keeps vault and keys)
	@echo "$(YELLOW)This will remove:$(RESET)"
	@echo "  - ansible.cfg"
	@echo "  - inventory/hosts.yml"
	@echo "  - inventory/bootstrap.yml"
	@echo "  - group_vars/all/main.yml"
	@echo "  - client-prep/"
	@echo "  - wazuh-client-prep.sh"
	@echo ""
	@echo "$(YELLOW)Keeping:$(RESET)"
	@echo "  - ~/.config/wazuh-deployment/.vault_password"
	@echo "  - group_vars/all/vault.yml"
	@echo "  - keys/"
	@echo ""
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	@rm -f ansible.cfg inventory/hosts.yml inventory/bootstrap.yml
	@rm -f group_vars/all/main.yml
	@rm -rf client-prep/ wazuh-client-prep.sh
	@echo "$(GREEN)Cleaned.$(RESET) Run 'make setup' to reconfigure."

clean-all: ## Remove ALL generated files including vault and keys
	@echo "$(RED)WARNING: This will remove ALL generated files including:$(RESET)"
	@echo "  - ~/.config/wazuh-deployment/.vault_password (CANNOT BE RECOVERED)"
	@echo "  - group_vars/all/vault.yml"
	@echo "  - keys/"
	@echo ""
	@read -p "Are you SURE? Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || exit 1
	@rm -f ansible.cfg ~/.config/wazuh-deployment/.vault_password
	@rm -f inventory/hosts.yml inventory/bootstrap.yml
	@rm -rf group_vars/all/ keys/ client-prep/ credentials/
	@rm -f wazuh-client-prep.sh
	@echo "$(GREEN)All files removed.$(RESET) Run 'make setup' to start fresh."
