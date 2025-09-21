.PHONY: check lint packer-validate images bootstrap apply verify-backups deploy-matrix net-scan

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

deploy-matrix:
	ansible-playbook ansible/playbooks/deploy-matrix.yaml

verify-backups:
	ansible-playbook ansible/playbooks/backups-verify.yaml

net-scan:
	./scripts/ralf-net-scan.sh --once
