.PHONY: help init plan apply destroy clean status fmt validate

help:
	@echo "CA2 Terraform + Libvirt - Available targets:"
	@echo "  init       - Initialize Terraform"
	@echo "  plan       - Plan infrastructure changes"
	@echo "  apply      - Apply infrastructure changes"
	@echo "  destroy    - Destroy infrastructure"
	@echo "  clean      - Clean Terraform files"
	@echo "  status     - Show current state"
	@echo "  fmt        - Format Terraform files"
	@echo "  validate   - Validate Terraform configuration"

init:
	terraform init

plan:
	terraform plan

apply:
	terraform apply

destroy:
	terraform destroy

clean:
	rm -rf .terraform/ .terraform.lock.hcl terraform.tfstate*

status:
	terraform state list

fmt:
	terraform fmt -recursive

validate:
	terraform validate

# Check if VMs are running
check-vms:
	@echo "Checking VM status..."
	@virsh list --name | grep ca2

# SSH into VMs
ssh-db:
	ssh -i ~/.ssh/id_rsa ubuntu@192.168.56.30

ssh-app:
	ssh -i ~/.ssh/id_rsa ubuntu@192.168.56.10

ssh-proxy:
	ssh -i ~/.ssh/id_rsa ubuntu@192.168.56.20

# Test connectivity
test:
	@echo "Testing H2 Database..."
	@nc -zv 192.168.56.30 9092 || echo "H2 not responding"
	@echo "Testing Bookstore..."
	@curl -s http://192.168.56.10:8080/books | head -c 100
	@echo "\nTesting Proxy..."
	@curl -s http://192.168.56.20/books | head -c 100
