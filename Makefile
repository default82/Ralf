SHELL := /usr/bin/env bash
ANSIBLE_DIR ?= ansible
INVENTORY ?= $(ANSIBLE_DIR)/inventories/home/hosts.yml
PLAYBOOK_SITE ?= $(ANSIBLE_DIR)/playbooks/site.yml
PLAYBOOK_BACKUP ?= $(ANSIBLE_DIR)/playbooks/backup.yml
ANSIBLE_CFG ?= $(ANSIBLE_DIR)/ansible.cfg
ANSIBLE_FLAGS ?=
TOFU_BIN ?= tofu
TOFU_DIR ?= infra
PRE_COMMIT ?= pre-commit

export ANSIBLE_CONFIG := $(ANSIBLE_CFG)

.PHONY: lint validate preflight plan apply smoke backup-check tofu-plan ansible-plan install

lint:
@echo "==> Running pre-commit hooks"
$(PRE_COMMIT) run --all-files

validate: tofu-plan ansible-plan

preflight:
@echo "==> Running Proxmox preflight checks"
./scripts/preflight.sh

install:
@echo "==> Launching graphical installer"
./scripts/install-gui.sh

plan:
@$(MAKE) tofu-plan PLAN_MODE=plan
@echo "==> Running Ansible check mode"
ANSIBLE_NOCOWS=1 ansible-playbook -i $(INVENTORY) $(PLAYBOOK_SITE) --check --diff $(ANSIBLE_FLAGS)

apply:
@$(MAKE) tofu-plan PLAN_MODE=apply
@echo "==> Applying Ansible configuration"
ANSIBLE_NOCOWS=1 ansible-playbook -i $(INVENTORY) $(PLAYBOOK_SITE) $(ANSIBLE_FLAGS)

smoke:
@echo "==> Executing smoke tests"
./scripts/smoke.sh

backup-check:
@echo "==> Validating Borgmatic backups"
ANSIBLE_NOCOWS=1 ansible-playbook -i $(INVENTORY) $(PLAYBOOK_BACKUP) $(ANSIBLE_FLAGS)

# Internal helpers -----------------------------------------------------------

tofu-plan:
@if find $(TOFU_DIR) -maxdepth 1 -name '*.tf' -print -quit >/dev/null; then \
if [ "$(PLAN_MODE)" = "apply" ]; then \
echo "==> Applying OpenTofu changes"; \
$(TOFU_BIN) -chdir=$(TOFU_DIR) apply -auto-approve; \
else \
echo "==> Planning OpenTofu changes"; \
$(TOFU_BIN) -chdir=$(TOFU_DIR) fmt -check; \
$(TOFU_BIN) -chdir=$(TOFU_DIR) validate; \
$(TOFU_BIN) -chdir=$(TOFU_DIR) plan; \
fi; \
else \
echo "==> No OpenTofu configuration detected in $(TOFU_DIR); skipping"; \
fi

ansible-plan:
@echo "==> Performing Ansible syntax check"
ANSIBLE_NOCOWS=1 ansible-playbook -i $(INVENTORY) $(PLAYBOOK_SITE) --syntax-check $(ANSIBLE_FLAGS)
