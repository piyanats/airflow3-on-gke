# Using External PostgreSQL with Airflow on GKE

This guide explains how to configure Airflow to use an external PostgreSQL database instead of the bundled PostgreSQL pod.

## Why Use External PostgreSQL?

External PostgreSQL (like Cloud SQL) provides:
- ✅ Managed service with automatic backups
- ✅ High availability and disaster recovery
- ✅ Better performance and scalability
- ✅ Automatic updates and maintenance
- ✅ Point-in-time recovery
- ✅ No need to manage database pods

## Option 1: Using Google Cloud SQL (Recommended for GCP)

### Step 1: Create Cloud SQL Instance

Run the provided script:

```bash
./scripts/create-cloud-sql.sh
```

Or manually:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export INSTANCE_NAME="airflow-db"

# Create Cloud SQL instance
gcloud sql instances create $INSTANCE_NAME \
    --database-version=POSTGRES_15 \
    --tier=db-custom-2-7680 \
    --region=$REGION \
    --network=default \
    --no-assign-ip \
    --database-flags=max_connections=200

# Create database
gcloud sql databases create airflow \
    --instance=$INSTANCE_NAME

# Create user
gcloud sql users create airflow \
    --instance=$INSTANCE_NAME \
    --password=CHANGE_THIS_PASSWORD
```

### Step 2: Configure Airflow to Use Cloud SQL

Create a custom values file `values-cloudsql.yaml`:

```yaml
airflow:
  config:
    # Disable bundled PostgreSQL
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:PASSWORD@/airflow?host=/cloudsql/PROJECT:REGION:INSTANCE_NAME

postgresql:
  # Disable bundled PostgreSQL
  enabled: false

# Enable Cloud SQL Proxy sidecar
cloudSqlProxy:
  enabled: true
  instances:
    - project: YOUR_PROJECT_ID
      region: us-central1
      instance: airflow-db
```

### Step 3: Install with Cloud SQL

```bash
helm upgrade --install airflow ./airflow-helm \
    --namespace=default \
    -f values-cloudsql.yaml \
    --wait
```

## Option 2: Using Cloud SQL with Private IP

### Step 1: Create Cloud SQL with Private IP

```bash
# Create instance with private IP
gcloud sql instances create $INSTANCE_NAME \
    --database-version=POSTGRES_15 \
    --tier=db-custom-2-7680 \
    --region=$REGION \
    --network=default \
    --no-assign-ip

# Get private IP
PRIVATE_IP=$(gcloud sql instances describe $INSTANCE_NAME \
    --format='get(ipAddresses[0].ipAddress)')

echo "Private IP: $PRIVATE_IP"
```

### Step 2: Configure Airflow

```yaml
airflow:
  config:
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:PASSWORD@PRIVATE_IP:5432/airflow

postgresql:
  enabled: false
```

## Option 3: Using External PostgreSQL (Any Provider)

For any external PostgreSQL database:

### Step 1: Prepare Database

1. Create database: `airflow`
2. Create user: `airflow` with password
3. Grant permissions:
   ```sql
   GRANT ALL PRIVILEGES ON DATABASE airflow TO airflow;
   ```

### Step 2: Create Kubernetes Secret

```bash
kubectl create secret generic airflow-db-secret \
    --from-literal=connection="postgresql+psycopg2://USER:PASSWORD@HOST:5432/DATABASE" \
    -n default
```

### Step 3: Configure values.yaml

```yaml
airflow:
  config:
    # Use secret reference
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:PASSWORD@your-db-host:5432/airflow

postgresql:
  # Disable bundled PostgreSQL
  enabled: false
```

## Option 4: Using Cloud SQL with Workload Identity (Most Secure)

### Step 1: Set up Workload Identity

```bash
# Create service account
gcloud iam service-accounts create airflow-db-sa \
    --display-name="Airflow DB Service Account"

# Grant Cloud SQL Client role
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:airflow-db-sa@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/cloudsql.client"

# Bind Kubernetes SA to GCP SA
gcloud iam service-accounts add-iam-policy-binding \
    airflow-db-sa@$PROJECT_ID.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:$PROJECT_ID.svc.id.goog[default/airflow]"
```

### Step 2: Configure Helm Values

```yaml
serviceAccount:
  create: true
  name: airflow
  annotations:
    iam.gke.io/gcp-service-account: airflow-db-sa@PROJECT_ID.iam.gserviceaccount.com

airflow:
  config:
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:PASSWORD@/airflow?host=/cloudsql/PROJECT:REGION:INSTANCE

postgresql:
  enabled: false

# Cloud SQL Proxy sidecar
extraContainers:
  - name: cloud-sql-proxy
    image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:latest
    args:
      - "--structured-logs"
      - "--port=5432"
      - "PROJECT:REGION:INSTANCE"
    securityContext:
      runAsNonRoot: true
```

## Configuration Examples

### Minimal External DB Configuration

```yaml
# values-external-db.yaml
airflow:
  config:
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:password@postgres-host:5432/airflow

postgresql:
  enabled: false
```

### Production Cloud SQL Configuration

```yaml
# values-cloudsql-production.yaml
airflow:
  config:
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:PASSWORD@/airflow?host=/cloudsql/PROJECT:REGION:INSTANCE
    AIRFLOW__DATABASE__SQL_ALCHEMY_POOL_SIZE: "10"
    AIRFLOW__DATABASE__SQL_ALCHEMY_MAX_OVERFLOW: "20"
    AIRFLOW__DATABASE__SQL_ALCHEMY_POOL_RECYCLE: "3600"
    AIRFLOW__DATABASE__SQL_ALCHEMY_POOL_PRE_PING: "True"

postgresql:
  enabled: false

serviceAccount:
  annotations:
    iam.gke.io/gcp-service-account: airflow-db-sa@PROJECT_ID.iam.gserviceaccount.com
```

## Connection String Formats

### Standard TCP Connection
```
postgresql+psycopg2://USERNAME:PASSWORD@HOST:PORT/DATABASE
```

### Cloud SQL with Unix Socket
```
postgresql+psycopg2://USERNAME:PASSWORD@/DATABASE?host=/cloudsql/PROJECT:REGION:INSTANCE
```

### With SSL
```
postgresql+psycopg2://USERNAME:PASSWORD@HOST:PORT/DATABASE?sslmode=require
```

### With Connection Pooling Parameters
```
postgresql+psycopg2://USER:PASS@HOST:PORT/DB?pool_size=10&max_overflow=20
```

## Database Requirements

- PostgreSQL 12+
- Extensions needed:
  - `pg_trgm` (for search)
  - `btree_gin` (for indexing)

## Database Initialization

When using external database, Airflow will automatically:

1. Run migrations on first start (via init container)
2. Create necessary tables and indexes
3. Create admin user (if configured)

You can verify with:

```bash
# Check database connection
kubectl exec -n default deployment/airflow-webserver -- airflow db check

# Check database version
kubectl exec -n default deployment/airflow-webserver -- airflow db shell
```

## Troubleshooting

### Connection Refused

```bash
# Test connectivity from pod
kubectl exec -it deployment/airflow-webserver -n default -- \
    psql "postgresql://airflow:PASSWORD@HOST:5432/airflow" -c "SELECT 1;"
```

### SSL/TLS Issues

Add SSL mode to connection string:
```
?sslmode=require
```

Or disable for testing (not recommended for production):
```
?sslmode=disable
```

### Cloud SQL Connection Issues

Check Cloud SQL Proxy logs:
```bash
kubectl logs -n default deployment/airflow-webserver -c cloud-sql-proxy
```

Verify instance connection name:
```bash
gcloud sql instances describe INSTANCE_NAME \
    --format='get(connectionName)'
```

### Authentication Issues

1. Verify credentials in secret
2. Check user permissions in database
3. Verify IP allowlist (for public IP connections)

## Performance Tuning

For better performance with external database:

```yaml
airflow:
  config:
    # Connection pool settings
    AIRFLOW__DATABASE__SQL_ALCHEMY_POOL_SIZE: "20"
    AIRFLOW__DATABASE__SQL_ALCHEMY_MAX_OVERFLOW: "40"
    AIRFLOW__DATABASE__SQL_ALCHEMY_POOL_RECYCLE: "3600"
    AIRFLOW__DATABASE__SQL_ALCHEMY_POOL_PRE_PING: "True"

    # Query optimization
    AIRFLOW__DATABASE__SQL_ALCHEMY_SCHEMA: "public"
    AIRFLOW__CORE__SQL_ALCHEMY_POOL_ENABLED: "True"
```

## Security Best Practices

1. **Use secrets** - Store credentials in Kubernetes secrets
2. **Enable SSL/TLS** - Always use encrypted connections
3. **Private IP** - Use private networking when possible
4. **Workload Identity** - Use GCP Workload Identity instead of passwords
5. **Least privilege** - Grant only necessary database permissions
6. **Rotate credentials** - Regularly rotate database passwords
7. **Network policies** - Restrict network access to database

## Migration from Bundled PostgreSQL

To migrate data from bundled PostgreSQL to external:

```bash
# 1. Backup existing database
./scripts/backup.sh

# 2. Export data
kubectl exec -n default deployment/postgres -- \
    pg_dump -U airflow airflow > airflow-backup.sql

# 3. Import to external database
psql "postgresql://airflow:PASSWORD@HOST:5432/airflow" < airflow-backup.sql

# 4. Update Helm values
helm upgrade airflow ./airflow-helm \
    -f values-external-db.yaml

# 5. Verify migration
kubectl exec -n default deployment/airflow-webserver -- airflow db check
```

## Examples Repository

See `examples/` directory for:
- `values-cloudsql.yaml` - Cloud SQL configuration
- `values-external-db.yaml` - Generic external DB configuration
- `values-cloudsql-workload-identity.yaml` - Secure Cloud SQL setup

## Additional Resources

- [Cloud SQL Documentation](https://cloud.google.com/sql/docs)
- [Airflow Database Configuration](https://airflow.apache.org/docs/apache-airflow/stable/howto/set-up-database.html)
- [Cloud SQL Proxy](https://cloud.google.com/sql/docs/postgres/connect-kubernetes-engine)
