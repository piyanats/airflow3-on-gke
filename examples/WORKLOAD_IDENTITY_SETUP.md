# Workload Identity Setup Guide

This guide explains how to set up GKE Workload Identity for Apache Airflow on GKE.

## What is Workload Identity?

Workload Identity is the recommended way for your applications running on GKE to access Google Cloud services. It provides:

- **Keyless authentication**: No service account keys needed
- **Auto-rotation**: Credentials are automatically rotated
- **Least privilege**: Fine-grained access control per service account
- **Audit logging**: Track who accessed what resources
- **Pod-level security**: Each pod gets its own identity

## Prerequisites

1. GKE cluster with Workload Identity enabled
2. Google Cloud project with necessary APIs enabled
3. `gcloud` CLI configured

## Quick Setup (Automated)

The easiest way to set up Workload Identity is using the provided script:

```bash
# Set your project ID
export GCP_PROJECT_ID="your-project-id"
export NAMESPACE="default"

# Run the setup script
./scripts/create-gcp-resources.sh
```

This script will:
1. Create a GCP service account (`airflow-sa`)
2. Grant necessary IAM permissions
3. Create Workload Identity binding
4. Output the annotation to add to your `values.yaml`

## Manual Setup

### Step 1: Create GCP Service Account

```bash
# Create service account
gcloud iam service-accounts create airflow-sa \
    --display-name="Airflow Service Account" \
    --project=YOUR-PROJECT-ID
```

### Step 2: Grant IAM Permissions

Grant the necessary roles based on your use case:

#### For GCS Access (Remote Logging, DAGs Storage)
```bash
gcloud projects add-iam-policy-binding YOUR-PROJECT-ID \
    --member="serviceAccount:airflow-sa@YOUR-PROJECT-ID.iam.gserviceaccount.com" \
    --role="roles/storage.admin"
```

#### For BigQuery Access
```bash
gcloud projects add-iam-policy-binding YOUR-PROJECT-ID \
    --member="serviceAccount:airflow-sa@YOUR-PROJECT-ID.iam.gserviceaccount.com" \
    --role="roles/bigquery.dataEditor"

gcloud projects add-iam-policy-binding YOUR-PROJECT-ID \
    --member="serviceAccount:airflow-sa@YOUR-PROJECT-ID.iam.gserviceaccount.com" \
    --role="roles/bigquery.jobUser"
```

#### For Cloud SQL Access (separate service account recommended)
```bash
# Create separate service account for Cloud SQL
gcloud iam service-accounts create airflow-db-sa \
    --display-name="Airflow Cloud SQL Service Account" \
    --project=YOUR-PROJECT-ID

# Grant Cloud SQL Client role
gcloud projects add-iam-policy-binding YOUR-PROJECT-ID \
    --member="serviceAccount:airflow-db-sa@YOUR-PROJECT-ID.iam.gserviceaccount.com" \
    --role="roles/cloudsql.client"
```

### Step 3: Create Workload Identity Binding

Bind the Kubernetes service account to the GCP service account:

```bash
# For general Airflow access
gcloud iam service-accounts add-iam-policy-binding \
    airflow-sa@YOUR-PROJECT-ID.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:YOUR-PROJECT-ID.svc.id.goog[default/airflow]" \
    --project=YOUR-PROJECT-ID

# For Cloud SQL access (if using separate service account)
gcloud iam service-accounts add-iam-policy-binding \
    airflow-db-sa@YOUR-PROJECT-ID.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:YOUR-PROJECT-ID.svc.id.goog[default/airflow]" \
    --project=YOUR-PROJECT-ID
```

### Step 4: Update Helm Values

Update your `values.yaml` or use one of the example configurations:

```yaml
serviceAccount:
  create: true
  name: "airflow"
  annotations:
    iam.gke.io/gcp-service-account: airflow-sa@YOUR-PROJECT-ID.iam.gserviceaccount.com
```

### Step 5: Deploy or Upgrade Airflow

```bash
# Install new deployment
helm install airflow ./airflow-helm -f values.yaml

# Or upgrade existing deployment
helm upgrade airflow ./airflow-helm -f values.yaml
```

## Configuration Examples

### Example 1: Standard Airflow with GCS Remote Logging

Use: `examples/values-production.yaml`

```yaml
serviceAccount:
  annotations:
    iam.gke.io/gcp-service-account: airflow-sa@YOUR-PROJECT-ID.iam.gserviceaccount.com

airflow:
  config:
    AIRFLOW__LOGGING__REMOTE_LOGGING: "True"
    AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER: "gs://your-bucket/airflow/logs"
```

Required roles:
- `roles/storage.admin` (or more specific storage roles)

### Example 2: Cloud SQL with Workload Identity

Use: `examples/values-cloudsql.yaml`

```yaml
serviceAccount:
  annotations:
    iam.gke.io/gcp-service-account: airflow-db-sa@YOUR-PROJECT-ID.iam.gserviceaccount.com
```

Required roles:
- `roles/cloudsql.client`

### Example 3: Multi-Service Access

For Airflow that needs access to GCS, BigQuery, and other services:

```yaml
serviceAccount:
  annotations:
    iam.gke.io/gcp-service-account: airflow-sa@YOUR-PROJECT-ID.iam.gserviceaccount.com
```

Required roles:
- `roles/storage.admin`
- `roles/bigquery.dataEditor`
- `roles/bigquery.jobUser`
- `roles/dataproc.editor` (if using Dataproc)
- `roles/pubsub.editor` (if using Pub/Sub)

## Verification

### Verify Workload Identity Binding

```bash
# Check IAM policy binding
gcloud iam service-accounts get-iam-policy \
    airflow-sa@YOUR-PROJECT-ID.iam.gserviceaccount.com
```

Expected output should include:
```yaml
bindings:
- members:
  - serviceAccount:YOUR-PROJECT-ID.svc.id.goog[default/airflow]
  role: roles/iam.workloadIdentityUser
```

### Test from Pod

Deploy Airflow and test from within a pod:

```bash
# Get pod name
kubectl get pods -n default | grep webserver

# Exec into pod
kubectl exec -it airflow-webserver-xxx -n default -- bash

# Test GCP authentication
gcloud auth list

# Test GCS access
gsutil ls gs://your-bucket/

# Test BigQuery access
bq ls
```

## Troubleshooting

### Issue: "Permission denied" errors

**Cause**: GCP service account doesn't have necessary permissions

**Solution**: Grant the required IAM roles to your GCP service account

```bash
gcloud projects add-iam-policy-binding YOUR-PROJECT-ID \
    --member="serviceAccount:airflow-sa@YOUR-PROJECT-ID.iam.gserviceaccount.com" \
    --role="roles/REQUIRED_ROLE"
```

### Issue: "Application Default Credentials not found"

**Cause**: Workload Identity annotation not set or binding not created

**Solution**:
1. Verify the annotation in your values.yaml
2. Check the Workload Identity binding exists
3. Restart the pods after adding the annotation

```bash
# Delete pods to pick up new annotation
kubectl delete pods -l app=airflow
```

### Issue: "Invalid JWT token"

**Cause**: Workload Identity not enabled on cluster or node pool

**Solution**: Ensure your GKE cluster has Workload Identity enabled

```bash
# Check cluster Workload Identity status
gcloud container clusters describe CLUSTER_NAME \
    --zone=ZONE \
    --project=PROJECT_ID \
    --format="value(workloadIdentityConfig.workloadPool)"
```

Expected output: `YOUR-PROJECT-ID.svc.id.goog`

### Issue: Wrong service account being used

**Cause**: Pods not using the correct Kubernetes service account

**Solution**: Verify pods are using the correct service account

```bash
# Check pod service account
kubectl get pods airflow-webserver-xxx -n default -o yaml | grep serviceAccountName
```

Expected output: `serviceAccountName: airflow`

## Security Best Practices

1. **Principle of Least Privilege**: Only grant the minimum required permissions
2. **Separate Service Accounts**: Use different service accounts for different purposes
   - `airflow-sa` for general Airflow operations
   - `airflow-db-sa` for Cloud SQL access
3. **Audit Logging**: Enable Cloud Audit Logs to track access
4. **Regular Review**: Periodically review and remove unused permissions
5. **No Service Account Keys**: Never create or use JSON service account keys

## Additional Resources

- [GKE Workload Identity Documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
- [IAM Roles Reference](https://cloud.google.com/iam/docs/understanding-roles)
- [Cloud SQL Proxy with Workload Identity](https://cloud.google.com/sql/docs/postgres/connect-kubernetes-engine)
- [Airflow GCP Integration](https://airflow.apache.org/docs/apache-airflow-providers-google/stable/index.html)

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review the GKE Workload Identity documentation
3. Check Airflow logs: `kubectl logs -f airflow-webserver-xxx`
4. Open an issue in the project repository
