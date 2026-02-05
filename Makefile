# Wazuh Deployment Makefile
# Common operations for deploying and managing Wazuh infrastructure
#
# Usage: make <target>
# Run 'make help' to see all available targets

.PHONY: help setup setup-tui deploy deploy-bootstrap deploy-indexer deploy-manager \
        deploy-dashboard deploy-agent health backup restore upgrade check status \
        unlock vault-view vault-edit vault-rotate certs-check certs-rotate clean \
        monitoring test lint

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
	@grep -E '^(setup|setup-tui|check):.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  $(CYAN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Deployment:$(RESET)"
	@grep -E '^deploy[^:]*:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  $(CYAN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Operations:$(RESET)"
	@grep -E '^(health|status|backup|restore|upgrade|unlock|monitoring):.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  $(CYAN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Security:$(RESET)"
	@grep -E '^(vault-|certs-)[^:]*:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  $(CYAN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Development:$(RESET)"
	@grep -E '^(test|lint|clean):.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  $(CYAN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Examples:$(RESET)"
	@echo "  make setup               # Run interactive CLI setup"
	@echo "  make deploy-bootstrap    # First-time deployment with bootstrap"
	@echo "  make deploy              # Regular deployment"
	@echo "  make status              # Quick health check"

#═══════════════════════════════════════════════════════════════════════════════
# Setup
#═══════════════════════════════════════════════════════════════════════════════

setup: ## Run interactive CLI setup wizard
	@./setup.sh

setup-tui: ## Run beautiful TUI setup (requires gum)
	@./setup-tui.sh

check: ## Validate prerequisites and configuration
	@echo "$(CYAN)Checking prerequisites...$(RESET)"
	@command -v ansible >/dev/null 2>&1 || { echo "$(RED)Error: ansible not found$(RESET)"; exit 1; }
	@command -v ansible-playbook >/dev/null 2>&1 || { echo "$(RED)Error: ansible-playbook not found$(RESET)"; exit 1; }
	@echo "$(GREEN)✓$(RESET) Ansible: $$(ansible --version | head -1)"
	@if [ -f inventory/hosts.yml ]; then \
		echo "$(GREEN)✓$(RESET) Inventory: inventory/hosts.yml"; \
	else \
		echo "$(YELLOW)⚠$(RESET) Inventory not found - run 'make setup' first"; \
	fi
	@if [ -f .vault_password ]; then \
		echo "$(GREEN)✓$(RESET) Vault password: .vault_password"; \
	else \
		echo "$(YELLOW)⚠$(RESET) Vault password not found"; \
	fi
	@if [ -f group_vars/all/vault.yml ]; then \
		echo "$(GREEN)✓$(RESET) Vault: group_vars/all/vault.yml (encrypted)"; \
	else \
		echo "$(YELLOW)⚠$(RESET) Vault not configured"; \
	fi
	@echo ""
	@echo "$(CYAN)Checking connectivity...$(RESET)"
	@ansible all -m ping --one-line 2>/dev/null || echo "$(YELLOW)⚠$(RESET) Could not reach all hosts"

#═══════════════════════════════════════════════════════════════════════════════
# Deployment
#═══════════════════════════════════════════════════════════════════════════════

deploy: ## Deploy all Wazuh components
	@echo "$(CYAN)Deploying Wazuh stack...$(RESET)"
	ansible-playbook site.yml

deploy-bootstrap: ## First-time deployment (bootstrap + all components)
	@echo "$(CYAN)Running bootstrap + full deployment...$(RESET)"
	ansible-playbook site.yml --tags bootstrap,all --ask-pass

deploy-check: ## Dry-run deployment (no changes)
	@echo "$(CYAN)Running deployment in check mode...$(RESET)"
	ansible-playbook site.yml --check --diff

deploy-indexer: ## Deploy only indexer nodes
	@echo "$(CYAN)Deploying indexers...$(RESET)"
	ansible-playbook site.yml --tags indexer

deploy-manager: ## Deploy only manager nodes
	@echo "$(CYAN)Deploying managers...$(RESET)"
	ansible-playbook site.yml --tags manager

deploy-dashboard: ## Deploy only dashboard nodes
	@echo "$(CYAN)Deploying dashboards...$(RESET)"
	ansible-playbook site.yml --tags dashboard

deploy-agent: ## Deploy agents to monitored hosts
	@echo "$(CYAN)Deploying agents...$(RESET)"
	ansible-playbook site.yml --tags agent

#═══════════════════════════════════════════════════════════════════════════════
# Operations
#═══════════════════════════════════════════════════════════════════════════════

health: ## Run comprehensive health check
	@echo "$(CYAN)Running health check...$(RESET)"
	ansible-playbook playbooks/health-check.yml

status: ## Quick status check of all services
	@if [ -f scripts/status.sh ]; then \
		./scripts/status.sh; \
	else \
		echo "$(CYAN)Checking service status...$(RESET)"; \
		ansible all -m shell -a "systemctl is-active wazuh-indexer wazuh-manager wazuh-dashboard wazuh-agent 2>/dev/null || true" --one-line; \
	fi

backup: ## Create backup of Wazuh data
	@echo "$(CYAN)Creating backup...$(RESET)"
	ansible-playbook playbooks/backup.yml

restore: ## Restore from backup (requires BACKUP_ID)
	@if [ -z "$(BACKUP_ID)" ]; then \
		echo "$(RED)Error: BACKUP_ID required$(RESET)"; \
		echo "Usage: make restore BACKUP_ID=20260101T120000"; \
		exit 1; \
	fi
	@echo "$(CYAN)Restoring from backup $(BACKUP_ID)...$(RESET)"
	ansible-playbook playbooks/restore.yml -e "restore_from=$(BACKUP_ID)"

upgrade: ## Upgrade Wazuh to version in group_vars
	@echo "$(CYAN)Running upgrade...$(RESET)"
	ansible-playbook playbooks/upgrade.yml

upgrade-check: ## Check available upgrades (no changes)
	@echo "$(CYAN)Checking for available upgrades...$(RESET)"
	ansible-playbook playbooks/upgrade.yml --tags check

unlock: ## Unlock deployment user for new deployment
	@echo "$(CYAN)Unlocking deployment user...$(RESET)"
	ansible-playbook unlock-deploy-user.yml

monitoring: ## Enable Prometheus monitoring exporters
	@echo "$(CYAN)Deploying Prometheus exporters...$(RESET)"
	ansible-playbook site.yml --tags monitoring -e wazuh_monitoring_enabled=true

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
		ansible-playbook playbooks/rotate-credentials.yml; \
	else \
		./scripts/manage-vault.sh rotate; \
	fi

vault-rekey: ## Change vault encryption password
	@./scripts/manage-vault.sh rekey

certs-check: ## Check certificate expiration
	@echo "$(CYAN)Checking certificate expiration...$(RESET)"
	ansible-playbook playbooks/certificate-management.yml --tags check-expiry

certs-rotate: ## Rotate all certificates
	@echo "$(CYAN)Rotating certificates...$(RESET)"
	ansible-playbook playbooks/certificate-management.yml --tags rotate

certs-renew: ## Renew expiring certificates
	@echo "$(CYAN)Renewing expiring certificates...$(RESET)"
	ansible-playbook playbooks/certificate-management.yml --tags renew

#═══════════════════════════════════════════════════════════════════════════════
# Development
#═══════════════════════════════════════════════════════════════════════════════

test: ## Run Ansible syntax and lint checks
	@echo "$(CYAN)Running syntax check...$(RESET)"
	ansible-playbook site.yml --syntax-check
	@echo "$(CYAN)Running lint...$(RESET)"
	@if command -v ansible-lint >/dev/null 2>&1; then \
		ansible-lint site.yml roles/; \
	else \
		echo "$(YELLOW)⚠$(RESET) ansible-lint not installed, skipping"; \
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
	@echo "  - .vault_password"
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
	@echo "  - .vault_password (CANNOT BE RECOVERED)"
	@echo "  - group_vars/all/vault.yml"
	@echo "  - keys/"
	@echo ""
	@read -p "Are you SURE? Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || exit 1
	@rm -f ansible.cfg .vault_password
	@rm -f inventory/hosts.yml inventory/bootstrap.yml
	@rm -rf group_vars/all/ keys/ client-prep/ credentials/
	@rm -f wazuh-client-prep.sh
	@echo "$(GREEN)All files removed.$(RESET) Run 'make setup' to start fresh."
