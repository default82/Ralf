.PHONY: check lint packer-validate images bootstrap apply verify-backups ai-check ai-pr

check: lint packer-validate

lint:
	yamllint inventory ansible/playbooks network architecture.yaml
	ansible-lint ansible/playbooks

packer-validate:
	packer validate -var-file=images/golden/vars.pkr.hcl.example images/golden/lxc-debian-bookworm.pkr.hcl
	packer validate -var-file=images/golden/vars.pkr.hcl.example images/golden/vm-debian-bookworm.pkr.hcl

images:
	packer build -var-file=images/golden/vars.pkr.hcl.example images/golden/lxc-debian-bookworm.pkr.hcl
	packer build -var-file=images/golden/vars.pkr.hcl.example images/golden/vm-debian-bookworm.pkr.hcl

bootstrap:
	ansible-playbook ansible/playbooks/bootstrap-proxmox.yaml

apply:
	@if [ "$${CORE_ONLY:-false}" = "true" ]; then \
		ansible-playbook ansible/playbooks/deploy-core.yaml; \
	elif [ "$${SERVICES_ONLY:-false}" = "true" ]; then \
		ansible-playbook ansible/playbooks/deploy-services.yaml; \
	else \
		ansible-playbook ansible/playbooks/site.yaml; \
	fi

verify-backups:
	ansible-playbook ansible/playbooks/backups-verify.yaml

ai-check:
	./scripts/ai_collect.sh reports/ai/context/latest.raw
	./scripts/ai_redact.sh reports/ai/context/latest.raw reports/ai/context/latest.redacted
	./scripts/ai_advisor.sh reports/ai/context/latest.redacted

ai-pr:
	@latest=$$(ls -1 reports/ai/*.txt 2>/dev/null | tail -n1); \
	if [ -z "$$latest" ]; then \
		echo "no AI advisor report available" >&2; exit 1; \
	fi; \
	if ! grep -q '^diff --git' "$$latest"; then \
		echo "latest report ($$latest) does not contain a diff" >&2; exit 1; \
	fi; \
	branch="ai/advisor-$$(date -u +%Y%m%d%H%M%S)"; \
	echo "creating branch $$branch"; \
	git checkout -b "$$branch"; \
	git add -A; \
	git commit -m "Apply AI advisor suggestions"; \
	if git remote get-url origin >/dev/null 2>&1; then \
		echo "pushing $$branch to origin"; \
		git push -u origin "$$branch"; \
	else \
		echo "origin remote missing, skipping push"; \
	fi
