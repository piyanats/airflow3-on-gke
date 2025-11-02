# Quick Start Guide - Apache Airflow 3 on GKE

This guide will help you get Apache Airflow 3 running on GKE in minutes.

## Prerequisites

- Google Cloud account with billing enabled
- `gcloud`, `kubectl`, and `helm` installed
- GCP project created

## Step 1: Set up GCP Project

```bash
# Login to GCP
gcloud auth login

# Set your project
export GCP_PROJECT_ID="your-project-id"
gcloud config set project $GCP_PROJECT_ID

# Enable required APIs
gcloud services enable container.googleapis.com
gcloud services enable compute.googleapis.com
```

## Step 2: Quick Install

```bash
# Clone the repository
git clone <your-repo-url>
cd airflow3-on-gke

# Run installation script
./install.sh
```

The script will:
1. Create a GKE cluster (if needed)
2. Install Airflow using Helm
3. Set up all required resources

## Step 3: Access Airflow UI

### Option A: Port Forward (Recommended for testing)

```bash
kubectl port-forward -n default svc/airflow-webserver 8080:8080
```

Then open: http://localhost:8080

### Option B: LoadBalancer (if enabled)

```bash
# Get external IP
kubectl get service airflow-webserver -n default

# Wait for EXTERNAL-IP to be assigned
# Then access: http://<EXTERNAL-IP>:8080
```

### Default Credentials

- Username: `admin`
- Password: `admin`

**IMPORTANT**: Change these credentials after first login!

## Step 4: Deploy Your First DAG

```bash
# Get the webserver pod name
POD_NAME=$(kubectl get pods -n default -l component=webserver -o jsonpath='{.items[0].metadata.name}')

# Copy example DAG
kubectl cp examples/dags/example_dag.py default/$POD_NAME:/opt/airflow/dags/

# Wait a few seconds for DAG to appear in UI
```

## Step 5: Verify Installation

```bash
# Run test script
./scripts/test-deployment.sh

# Check all pods are running
kubectl get pods -n default -l app=airflow

# View logs
kubectl logs -n default -l component=webserver --tail=50
```

## What's Next?

### Configure Git-Sync for DAGs

Edit `airflow-helm/values.yaml`:

```yaml
dags:
  gitSync:
    enabled: true
    repo: "https://github.com/your-org/your-dags.git"
    branch: "main"
    subPath: "dags"
```

Then upgrade:

```bash
./upgrade.sh
```

### Enable Ingress with Custom Domain

1. Install nginx ingress controller:
```bash
helm install nginx-ingress ingress-nginx/ingress-nginx
```

2. Update `airflow-helm/values.yaml`:
```yaml
ingress:
  enabled: true
  hosts:
    - host: airflow.yourdomain.com
```

3. Upgrade installation:
```bash
./upgrade.sh
```

### Set up Production Configuration

For production use, see [examples/values-production.yaml](examples/values-production.yaml)

Key production changes:
- Use Cloud SQL instead of PostgreSQL pod
- Enable remote logging to GCS
- Configure Workload Identity
- Enable HTTPS/TLS
- Increase replicas for HA
- Set up monitoring

## Common Commands

```bash
# View all pods
kubectl get pods -n default

# View webserver logs
kubectl logs -n default -l component=webserver -f

# View scheduler logs
kubectl logs -n default -l component=scheduler -f

# List DAGs
kubectl exec -n default deployment/airflow-webserver -- airflow dags list

# Get shell access
kubectl exec -it -n default deployment/airflow-webserver -- /bin/bash

# Upgrade Airflow
./upgrade.sh

# Uninstall Airflow
./uninstall.sh
```

## Troubleshooting

### Pods not starting

```bash
kubectl describe pod <pod-name> -n default
kubectl logs <pod-name> -n default
```

### Cannot access UI

```bash
# Check service
kubectl get service airflow-webserver -n default

# Use port-forward
kubectl port-forward -n default svc/airflow-webserver 8080:8080
```

### Database connection errors

```bash
# Check database pod
kubectl get pod -n default -l app=postgres

# Test connection
kubectl exec -n default deployment/airflow-webserver -- airflow db check
```

## Clean Up

To remove everything:

```bash
./uninstall.sh
```

This will:
1. Uninstall Airflow
2. Delete PVCs
3. Optionally delete the GKE cluster

## Resources

- Full documentation: [README.md](README.md)
- Production setup: [examples/values-production.yaml](examples/values-production.yaml)
- Development notes: [NOTES.md](NOTES.md)

## Support

For issues, check:
1. Pod logs: `kubectl logs <pod-name> -n default`
2. Pod events: `kubectl describe pod <pod-name> -n default`
3. Service status: `kubectl get all -n default`

For more help, see the main [README.md](README.md) or open an issue.
