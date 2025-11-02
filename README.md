# Apache Airflow 3 on Google Kubernetes Engine (GKE)

This repository contains Helm charts and scripts to deploy Apache Airflow 3 on Google Kubernetes Engine (GKE).

## Features

- Apache Airflow 3.0.0
- Kubernetes Executor
- PostgreSQL database
- Persistent storage for DAGs and logs
- Auto-scaling support
- Production-ready configuration
- Easy installation and management scripts

## Prerequisites

Before you begin, ensure you have the following installed:

- [Google Cloud SDK (gcloud)](https://cloud.google.com/sdk/docs/install)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm 3](https://helm.sh/docs/intro/install/)
- A GCP project with billing enabled
- Appropriate IAM permissions to create GKE clusters

## Quick Start

### 1. Clone this repository

```bash
git clone <your-repo-url>
cd airflow3-on-gke
```

### 2. Configure GCP credentials

```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

### 3. Install Airflow

Run the installation script:

```bash
./install.sh
```

The script will:
- Check prerequisites
- Create a GKE cluster (if it doesn't exist)
- Deploy Airflow using Helm
- Set up all necessary resources

### 4. Access Airflow UI

After installation completes, get the external IP:

```bash
kubectl get service airflow-webserver -n default
```

Or use port-forwarding:

```bash
kubectl port-forward -n default svc/airflow-webserver 8080:8080
```

Then visit: http://localhost:8080

**Default credentials:**
- Username: `admin`
- Password: `admin`

## Architecture

The deployment includes:

- **Webserver**: Serves the Airflow UI (1 replica, scalable)
- **Scheduler**: Schedules DAG runs (1 replica, scalable)
- **PostgreSQL**: Metadata database with persistent storage
- **Kubernetes Executor**: Runs tasks as individual Kubernetes pods
- **Persistent Volumes**: For DAGs and logs

## Using External PostgreSQL Database

For production use, it's recommended to use an external PostgreSQL database like Google Cloud SQL instead of the bundled PostgreSQL pod.

### Quick Setup with Cloud SQL

```bash
# Create Cloud SQL instance
./scripts/create-cloud-sql.sh

# Install Airflow with Cloud SQL
helm upgrade --install airflow ./airflow-helm \
    -f examples/values-cloudsql.yaml
```

See detailed guides:
- [Quick External DB Setup](docs/QUICK_EXTERNAL_DB_SETUP.md) - Quick start guide (Thai)
- [External PostgreSQL Guide](docs/EXTERNAL_POSTGRESQL.md) - Complete documentation

### Available Examples

- `examples/values-cloudsql.yaml` - Cloud SQL with Cloud SQL Proxy
- `examples/values-cloudsql-private-ip.yaml` - Cloud SQL with Private IP
- `examples/values-external-db.yaml` - Any external PostgreSQL

## Installing Custom Dependencies

To add custom Python packages or system dependencies to Airflow:

### Quick Setup

```bash
# 1. Edit requirements
vim docker/requirements.txt

# 2. Build custom image
export GCP_PROJECT_ID="your-project-id"
./scripts/build-custom-image.sh

# 3. Deploy with custom image
helm upgrade --install airflow ./airflow-helm \
    -f examples/values-custom-image.yaml
```

See detailed guides:
- [Quick Custom Dependencies Setup](docs/QUICK_CUSTOM_DEPS_SETUP.md) - Quick start guide (Thai)
- [Custom Dependencies Guide](docs/CUSTOM_DEPENDENCIES.md) - Complete documentation

### Available Dockerfiles

- `docker/Dockerfile` - Standard with UV package manager (10-100x faster than pip)
- `docker/Dockerfile.slim` - Lightweight with UV, Python only
- `docker/Dockerfile.multi-stage` - Optimized multi-stage build with UV
- `docker/Dockerfile.uv-fast` - Ultra-fast build maximizing UV's caching

All Dockerfiles now use **UV** - an extremely fast Python package installer written in Rust. Builds are 10-100x faster than pip!

## Configuration

### Environment Variables

You can customize the installation using environment variables:

```bash
export GCP_PROJECT_ID="your-project-id"
export CLUSTER_NAME="airflow-cluster"
export GCP_REGION="us-central1"
export GCP_ZONE="us-central1-a"
export NAMESPACE="default"
export RELEASE_NAME="airflow"
```

### Custom Values

To customize Airflow configuration, create a custom values file:

```bash
cp examples/values-custom.yaml my-values.yaml
# Edit my-values.yaml with your settings
```

Then install with custom values:

```bash
helm upgrade --install airflow ./airflow-helm \
  --namespace=default \
  --values=my-values.yaml
```

### Important Configuration Options

Edit `airflow-helm/values.yaml` or create a custom values file:

#### Executor Type

```yaml
airflow:
  config:
    AIRFLOW__CORE__EXECUTOR: KubernetesExecutor  # or CeleryExecutor
```

#### Database Connection

```yaml
airflow:
  config:
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://user:pass@host:5432/db
```

#### Resources

```yaml
webserver:
  resources:
    requests:
      cpu: "1000m"
      memory: "2Gi"
    limits:
      cpu: "2000m"
      memory: "4Gi"
```

#### Git-Sync for DAGs

```yaml
dags:
  gitSync:
    enabled: true
    repo: "https://github.com/your-org/your-dags-repo.git"
    branch: "main"
    subPath: "dags"
    interval: 60
```

#### Ingress (for custom domain)

```yaml
ingress:
  enabled: true
  className: "nginx"
  hosts:
    - host: airflow.yourdomain.com
      paths:
        - path: /
          pathType: Prefix
```

## Managing DAGs

### Option 1: Using Persistent Volume

Copy DAGs to the persistent volume:

```bash
# Get the webserver pod name
POD_NAME=$(kubectl get pods -n default -l component=webserver -o jsonpath='{.items[0].metadata.name}')

# Copy DAGs
kubectl cp examples/dags/example_dag.py default/$POD_NAME:/opt/airflow/dags/
```

### Option 2: Using Git-Sync

Configure git-sync in `values.yaml`:

```yaml
dags:
  gitSync:
    enabled: true
    repo: "https://github.com/your-org/airflow-dags.git"
    branch: "main"
    subPath: "dags"
    interval: 60
```

### Option 3: Build Custom Image

Create a Dockerfile with your DAGs:

```dockerfile
FROM apache/airflow:3.0.0-python3.12
COPY dags/ /opt/airflow/dags/
```

## GCP Integration

### Workload Identity

To use GCP services from Airflow:

1. Create a GCP service account:

```bash
gcloud iam service-accounts create airflow-sa \
    --display-name="Airflow Service Account"
```

2. Grant necessary permissions:

```bash
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
    --member="serviceAccount:airflow-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/storage.admin"
```

3. Bind Kubernetes service account to GCP service account:

```bash
gcloud iam service-accounts add-iam-policy-binding \
    airflow-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:YOUR_PROJECT_ID.svc.id.goog[default/airflow]"
```

4. Update `values.yaml`:

```yaml
serviceAccount:
  annotations:
    iam.gke.io/gcp-service-account: airflow-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com
```

### Remote Logging to GCS

Configure GCS for remote logging:

```yaml
airflow:
  config:
    AIRFLOW__LOGGING__REMOTE_LOGGING: "True"
    AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER: "gs://your-bucket/airflow/logs"
    AIRFLOW__LOGGING__REMOTE_LOG_CONN_ID: "google_cloud_default"
```

## Management Scripts

### Install

```bash
./install.sh
```

### Upgrade

```bash
./upgrade.sh
```

### Uninstall

```bash
./uninstall.sh
```

## Useful Commands

### Check pod status

```bash
kubectl get pods -n default -l app=airflow
```

### View logs

```bash
# Webserver logs
kubectl logs -n default -l component=webserver --tail=100 -f

# Scheduler logs
kubectl logs -n default -l component=scheduler --tail=100 -f
```

### Execute commands in Airflow

```bash
# Get shell access
kubectl exec -it -n default deployment/airflow-webserver -- /bin/bash

# Run Airflow CLI commands
kubectl exec -it -n default deployment/airflow-webserver -- airflow dags list
kubectl exec -it -n default deployment/airflow-webserver -- airflow users list
```

### Create admin user

```bash
kubectl exec -it -n default deployment/airflow-webserver -- \
  airflow users create \
    --username admin \
    --password admin \
    --firstname Admin \
    --lastname User \
    --role Admin \
    --email admin@example.com
```

### Scale deployments

```bash
# Scale webserver
kubectl scale deployment airflow-webserver -n default --replicas=3

# Scale scheduler
kubectl scale deployment airflow-scheduler -n default --replicas=2
```

### Database migration

```bash
kubectl exec -it -n default deployment/airflow-webserver -- airflow db migrate
```

## Monitoring

### Check cluster resources

```bash
kubectl top nodes
kubectl top pods -n default
```

### Check service endpoints

```bash
kubectl get endpoints -n default
```

### Describe resources

```bash
kubectl describe deployment airflow-webserver -n default
kubectl describe pod <pod-name> -n default
```

## Troubleshooting

### Pods not starting

```bash
# Check pod events
kubectl describe pod <pod-name> -n default

# Check logs
kubectl logs <pod-name> -n default
```

### Database connection issues

```bash
# Check PostgreSQL pod
kubectl get pod -n default -l app=postgres

# Check PostgreSQL logs
kubectl logs -n default -l app=postgres

# Test database connection
kubectl exec -it -n default deployment/airflow-webserver -- \
  airflow db check
```

### Persistent volume issues

```bash
# Check PVCs
kubectl get pvc -n default

# Check PVs
kubectl get pv
```

### Cannot access Airflow UI

```bash
# Check service
kubectl get service airflow-webserver -n default

# Check if LoadBalancer has external IP
kubectl describe service airflow-webserver -n default

# Use port-forward as alternative
kubectl port-forward -n default svc/airflow-webserver 8080:8080
```

## Security Considerations

1. **Change default credentials**: Update admin password after first login
2. **Use secrets**: Store sensitive data in Kubernetes secrets
3. **Enable RBAC**: Configure proper role-based access control
4. **Network policies**: Implement network policies to restrict traffic
5. **TLS/SSL**: Enable HTTPS for production deployments
6. **Workload Identity**: Use GCP Workload Identity instead of service account keys
7. **Secret backend**: Use GCP Secret Manager for storing connections and variables

## Upgrading Airflow

To upgrade to a newer version of Airflow:

1. Update the image tag in `values.yaml`:

```yaml
airflow:
  image:
    tag: "3.0.1-python3.12"
```

2. Run the upgrade script:

```bash
./upgrade.sh
```

## Cost Optimization

- Use preemptible nodes for non-critical workloads
- Configure autoscaling based on workload
- Use appropriate machine types
- Enable cluster autoscaler
- Set resource requests and limits appropriately
- Use regional persistent disks instead of zonal for HA

## Production Checklist

- [ ] Change default admin password
- [ ] Configure external database (Cloud SQL)
- [ ] Enable remote logging to GCS
- [ ] Set up monitoring and alerting
- [ ] Configure backups
- [ ] Enable HTTPS/TLS
- [ ] Set up proper RBAC
- [ ] Configure resource limits
- [ ] Set up CI/CD for DAG deployment
- [ ] Configure secrets management
- [ ] Set up disaster recovery plan
- [ ] Enable audit logging
- [ ] Configure network policies

## Resources

- [Apache Airflow Documentation](https://airflow.apache.org/docs/)
- [Airflow on Kubernetes](https://airflow.apache.org/docs/apache-airflow/stable/kubernetes.html)
- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [Helm Documentation](https://helm.sh/docs/)

## License

This project is provided as-is for educational and production use.

## Support

For issues and questions:
- Check the troubleshooting section
- Review Airflow logs
- Consult official Airflow documentation
- Open an issue in this repository
