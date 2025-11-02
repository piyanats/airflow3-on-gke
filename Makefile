.PHONY: help install uninstall upgrade status logs clean test

NAMESPACE ?= default
RELEASE_NAME ?= airflow

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

install: ## Install Airflow on GKE
	@echo "Installing Airflow..."
	./install.sh

uninstall: ## Uninstall Airflow
	@echo "Uninstalling Airflow..."
	./uninstall.sh

upgrade: ## Upgrade Airflow
	@echo "Upgrading Airflow..."
	./upgrade.sh

status: ## Check Airflow status
	@echo "Checking Airflow status..."
	@kubectl get pods -n $(NAMESPACE) -l app=airflow
	@echo ""
	@kubectl get services -n $(NAMESPACE) -l app=airflow

logs-webserver: ## Show webserver logs
	@kubectl logs -n $(NAMESPACE) -l component=webserver --tail=100 -f

logs-scheduler: ## Show scheduler logs
	@kubectl logs -n $(NAMESPACE) -l component=scheduler --tail=100 -f

shell-webserver: ## Get shell in webserver pod
	@kubectl exec -it -n $(NAMESPACE) deployment/$(RELEASE_NAME)-webserver -- /bin/bash

shell-scheduler: ## Get shell in scheduler pod
	@kubectl exec -it -n $(NAMESPACE) deployment/$(RELEASE_NAME)-scheduler -- /bin/bash

port-forward: ## Port forward webserver to localhost:8080
	@echo "Forwarding port 8080..."
	@echo "Access Airflow at http://localhost:8080"
	@kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-webserver 8080:8080

dag-list: ## List all DAGs
	@kubectl exec -n $(NAMESPACE) deployment/$(RELEASE_NAME)-webserver -- airflow dags list

users-list: ## List all users
	@kubectl exec -n $(NAMESPACE) deployment/$(RELEASE_NAME)-webserver -- airflow users list

db-check: ## Check database connection
	@kubectl exec -n $(NAMESPACE) deployment/$(RELEASE_NAME)-webserver -- airflow db check

db-migrate: ## Run database migration
	@kubectl exec -n $(NAMESPACE) deployment/$(RELEASE_NAME)-webserver -- airflow db migrate

test-dag: ## Test example DAG
	@kubectl exec -n $(NAMESPACE) deployment/$(RELEASE_NAME)-webserver -- \
		airflow dags test example_dag 2024-01-01

clean: ## Clean up local files
	@echo "Cleaning up..."
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.pyc" -delete
	@find . -type f -name "*.log" -delete

validate: ## Validate Helm chart
	@echo "Validating Helm chart..."
	@helm lint ./airflow-helm

template: ## Show Helm template output
	@helm template $(RELEASE_NAME) ./airflow-helm --namespace=$(NAMESPACE)

dry-run: ## Dry run Helm install
	@helm install $(RELEASE_NAME) ./airflow-helm \
		--namespace=$(NAMESPACE) \
		--dry-run --debug

get-ip: ## Get Airflow webserver external IP
	@kubectl get service $(RELEASE_NAME)-webserver -n $(NAMESPACE) \
		-o jsonpath='{.status.loadBalancer.ingress[0].ip}'

scale-webserver: ## Scale webserver (usage: make scale-webserver REPLICAS=3)
	@kubectl scale deployment $(RELEASE_NAME)-webserver \
		-n $(NAMESPACE) --replicas=$(REPLICAS)

scale-scheduler: ## Scale scheduler (usage: make scale-scheduler REPLICAS=2)
	@kubectl scale deployment $(RELEASE_NAME)-scheduler \
		-n $(NAMESPACE) --replicas=$(REPLICAS)

restart-webserver: ## Restart webserver
	@kubectl rollout restart deployment/$(RELEASE_NAME)-webserver -n $(NAMESPACE)

restart-scheduler: ## Restart scheduler
	@kubectl rollout restart deployment/$(RELEASE_NAME)-scheduler -n $(NAMESPACE)

backup-db: ## Backup database (requires pg_dump)
	@echo "Backing up database..."
	@kubectl exec -n $(NAMESPACE) deployment/postgres -- \
		pg_dump -U airflow airflow > backup-$$(date +%Y%m%d-%H%M%S).sql

describe-pods: ## Describe all Airflow pods
	@kubectl describe pods -n $(NAMESPACE) -l app=airflow

top: ## Show resource usage
	@kubectl top pods -n $(NAMESPACE) -l app=airflow

events: ## Show cluster events
	@kubectl get events -n $(NAMESPACE) --sort-by='.lastTimestamp'
