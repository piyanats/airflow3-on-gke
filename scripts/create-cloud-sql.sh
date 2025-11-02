#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID="${GCP_PROJECT_ID:-}"
REGION="${GCP_REGION:-us-central1}"
INSTANCE_NAME="${CLOUD_SQL_INSTANCE:-airflow-db}"
DATABASE_NAME="airflow"
DB_USER="airflow"
DB_PASSWORD="${DB_PASSWORD:-}"
TIER="${DB_TIER:-db-custom-2-7680}"  # 2 vCPU, 7.5 GB RAM
USE_PRIVATE_IP="${USE_PRIVATE_IP:-true}"

echo -e "${GREEN}=== Creating Cloud SQL Instance for Airflow ===${NC}"
echo ""

# Check prerequisites
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}Error: gcloud CLI is not installed${NC}"
    exit 1
fi

# Get GCP project ID if not set
if [ -z "$PROJECT_ID" ]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [ -z "$PROJECT_ID" ]; then
        echo -e "${RED}Error: GCP project ID is not set${NC}"
        echo "Set it using: export GCP_PROJECT_ID=your-project-id"
        exit 1
    fi
fi

# Generate password if not set
if [ -z "$DB_PASSWORD" ]; then
    DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    echo -e "${YELLOW}Generated password: $DB_PASSWORD${NC}"
    echo -e "${YELLOW}Please save this password securely!${NC}"
    echo ""
fi

echo "Configuration:"
echo "  Project ID: $PROJECT_ID"
echo "  Region: $REGION"
echo "  Instance Name: $INSTANCE_NAME"
echo "  Database: $DATABASE_NAME"
echo "  User: $DB_USER"
echo "  Tier: $TIER"
echo "  Private IP: $USE_PRIVATE_IP"
echo ""

read -p "Continue with these settings? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Enable required APIs
echo -e "${YELLOW}>>> Enabling required APIs...${NC}"
gcloud services enable sqladmin.googleapis.com \
    servicenetworking.googleapis.com \
    --project=$PROJECT_ID

# Check if instance already exists
if gcloud sql instances describe $INSTANCE_NAME --project=$PROJECT_ID &>/dev/null; then
    echo -e "${YELLOW}Instance $INSTANCE_NAME already exists!${NC}"
    read -p "Do you want to use the existing instance? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
    INSTANCE_EXISTS=true
else
    INSTANCE_EXISTS=false
fi

# Create Cloud SQL instance
if [ "$INSTANCE_EXISTS" = false ]; then
    echo -e "${YELLOW}>>> Creating Cloud SQL instance...${NC}"

    if [ "$USE_PRIVATE_IP" = "true" ]; then
        # Create with private IP
        gcloud sql instances create $INSTANCE_NAME \
            --database-version=POSTGRES_15 \
            --tier=$TIER \
            --region=$REGION \
            --network=default \
            --no-assign-ip \
            --database-flags=max_connections=200,shared_preload_libraries=pg_stat_statements \
            --enable-bin-log \
            --backup-start-time=03:00 \
            --maintenance-window-day=SUN \
            --maintenance-window-hour=04 \
            --project=$PROJECT_ID
    else
        # Create with public IP
        gcloud sql instances create $INSTANCE_NAME \
            --database-version=POSTGRES_15 \
            --tier=$TIER \
            --region=$REGION \
            --database-flags=max_connections=200,shared_preload_libraries=pg_stat_statements \
            --enable-bin-log \
            --backup-start-time=03:00 \
            --maintenance-window-day=SUN \
            --maintenance-window-hour=04 \
            --project=$PROJECT_ID
    fi

    echo -e "${GREEN}✓ Cloud SQL instance created${NC}"
else
    echo -e "${GREEN}✓ Using existing instance${NC}"
fi

# Wait for instance to be ready
echo -e "${YELLOW}>>> Waiting for instance to be ready...${NC}"
while [ "$(gcloud sql instances describe $INSTANCE_NAME --project=$PROJECT_ID --format='get(state)')" != "RUNNABLE" ]; do
    echo "Waiting..."
    sleep 5
done
echo -e "${GREEN}✓ Instance is ready${NC}"

# Create database
echo -e "${YELLOW}>>> Creating database...${NC}"
gcloud sql databases create $DATABASE_NAME \
    --instance=$INSTANCE_NAME \
    --project=$PROJECT_ID 2>/dev/null || \
    echo "Database already exists or creation failed"

# Create user
echo -e "${YELLOW}>>> Creating user...${NC}"
gcloud sql users create $DB_USER \
    --instance=$INSTANCE_NAME \
    --password="$DB_PASSWORD" \
    --project=$PROJECT_ID 2>/dev/null || \
    echo "User already exists or creation failed"

# Get connection information
echo -e "${YELLOW}>>> Getting connection information...${NC}"
CONNECTION_NAME=$(gcloud sql instances describe $INSTANCE_NAME \
    --project=$PROJECT_ID \
    --format='get(connectionName)')

if [ "$USE_PRIVATE_IP" = "true" ]; then
    PRIVATE_IP=$(gcloud sql instances describe $INSTANCE_NAME \
        --project=$PROJECT_ID \
        --format='get(ipAddresses[0].ipAddress)')
else
    PUBLIC_IP=$(gcloud sql instances describe $INSTANCE_NAME \
        --project=$PROJECT_ID \
        --format='get(ipAddresses[0].ipAddress)')
fi

# Create Kubernetes secret
echo -e "${YELLOW}>>> Creating Kubernetes secret...${NC}"
echo ""
read -p "Create Kubernetes secret for database credentials? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    NAMESPACE="${NAMESPACE:-default}"

    # Create connection string
    if [ "$USE_PRIVATE_IP" = "true" ]; then
        CONN_STRING="postgresql+psycopg2://${DB_USER}:${DB_PASSWORD}@${PRIVATE_IP}:5432/${DATABASE_NAME}"
    else
        CONN_STRING="postgresql+psycopg2://${DB_USER}:${DB_PASSWORD}@/airflow?host=/cloudsql/${CONNECTION_NAME}"
    fi

    kubectl create secret generic airflow-db-credentials \
        --from-literal=connection="$CONN_STRING" \
        --from-literal=password="$DB_PASSWORD" \
        --from-literal=user="$DB_USER" \
        --namespace=$NAMESPACE \
        --dry-run=client -o yaml | kubectl apply -f -

    echo -e "${GREEN}✓ Kubernetes secret created${NC}"
fi

# Output summary
echo ""
echo -e "${GREEN}=== Cloud SQL Instance Created Successfully ===${NC}"
echo ""
echo "Instance Details:"
echo "  Connection Name: $CONNECTION_NAME"
echo "  Database: $DATABASE_NAME"
echo "  User: $DB_USER"
echo "  Password: $DB_PASSWORD"

if [ "$USE_PRIVATE_IP" = "true" ]; then
    echo "  Private IP: $PRIVATE_IP"
else
    echo "  Public IP: $PUBLIC_IP"
fi

echo ""
echo "=== Airflow Configuration ==="
echo ""

if [ "$USE_PRIVATE_IP" = "true" ]; then
    echo "Add to your values.yaml:"
    echo ""
    echo "airflow:"
    echo "  config:"
    echo "    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://${DB_USER}:${DB_PASSWORD}@${PRIVATE_IP}:5432/${DATABASE_NAME}"
    echo ""
    echo "postgresql:"
    echo "  enabled: false"
else
    echo "Add to your values.yaml:"
    echo ""
    echo "airflow:"
    echo "  config:"
    echo "    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://${DB_USER}:${DB_PASSWORD}@/airflow?host=/cloudsql/${CONNECTION_NAME}"
    echo ""
    echo "postgresql:"
    echo "  enabled: false"
    echo ""
    echo "# Add Cloud SQL Proxy sidecar"
    echo "extraContainers:"
    echo "  - name: cloud-sql-proxy"
    echo "    image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:latest"
    echo "    args:"
    echo "      - \"--structured-logs\""
    echo "      - \"--port=5432\""
    echo "      - \"${CONNECTION_NAME}\""
fi

echo ""
echo "Or use the example file:"
echo "  examples/values-cloudsql.yaml"
echo ""

# Save configuration to file
CONFIG_FILE="cloud-sql-config.txt"
cat > $CONFIG_FILE <<EOF
Cloud SQL Configuration for Airflow
====================================

Instance Details:
  Connection Name: $CONNECTION_NAME
  Database: $DATABASE_NAME
  User: $DB_USER
  Password: $DB_PASSWORD
  $([ "$USE_PRIVATE_IP" = "true" ] && echo "Private IP: $PRIVATE_IP" || echo "Public IP: $PUBLIC_IP")

Connection String:
  $([ "$USE_PRIVATE_IP" = "true" ] && echo "postgresql+psycopg2://${DB_USER}:${DB_PASSWORD}@${PRIVATE_IP}:5432/${DATABASE_NAME}" || echo "postgresql+psycopg2://${DB_USER}:${DB_PASSWORD}@/airflow?host=/cloudsql/${CONNECTION_NAME}")

Created: $(date)
EOF

echo -e "${GREEN}Configuration saved to: $CONFIG_FILE${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT: Keep the password and configuration file secure!${NC}"
echo ""

# Optional: Test connection
echo ""
read -p "Test database connection from Cloud Shell? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ "$USE_PRIVATE_IP" = "true" ]; then
        echo "Testing connection to private IP..."
        gcloud sql connect $INSTANCE_NAME --user=$DB_USER --database=$DATABASE_NAME --project=$PROJECT_ID
    else
        echo "For public IP, you need to add your IP to authorized networks first."
    fi
fi

echo ""
echo -e "${GREEN}Setup complete!${NC}"
