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
BUCKET_NAME="${GCS_BUCKET_NAME:-${PROJECT_ID}-airflow-logs}"
SERVICE_ACCOUNT_NAME="airflow-sa"

echo -e "${GREEN}=== Creating GCP Resources for Airflow ===${NC}"
echo ""

# Get GCP project ID if not set
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: GCP project ID is not set${NC}"
    echo "Set it using: export GCP_PROJECT_ID=your-project-id"
    exit 1
fi

echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo "Bucket Name: $BUCKET_NAME"
echo "Service Account: $SERVICE_ACCOUNT_NAME"
echo ""

# Create GCS bucket for logs
echo -e "${YELLOW}>>> Creating GCS bucket for logs...${NC}"
gsutil mb -p $PROJECT_ID -l $REGION gs://$BUCKET_NAME/ 2>/dev/null || \
    echo "Bucket already exists or creation failed"

# Enable versioning on bucket
gsutil versioning set on gs://$BUCKET_NAME/

echo -e "${GREEN}Bucket created: gs://$BUCKET_NAME${NC}"

# Create service account
echo -e "${YELLOW}>>> Creating service account...${NC}"
gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
    --display-name="Airflow Service Account" \
    --project=$PROJECT_ID 2>/dev/null || \
    echo "Service account already exists"

# Grant permissions to service account
echo -e "${YELLOW}>>> Granting permissions...${NC}"

# Storage Admin for GCS
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/storage.admin" \
    --condition=None

# BigQuery Admin (if needed)
read -p "Grant BigQuery Admin role? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/bigquery.admin" \
        --condition=None
fi

# Cloud SQL Client (if using Cloud SQL)
read -p "Grant Cloud SQL Client role? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/cloudsql.client" \
        --condition=None
fi

echo -e "${GREEN}Permissions granted!${NC}"

# Set up Workload Identity
echo -e "${YELLOW}>>> Setting up Workload Identity...${NC}"
NAMESPACE="${NAMESPACE:-default}"
KSA_NAME="airflow"

gcloud iam service-accounts add-iam-policy-binding \
    ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/${KSA_NAME}]" \
    --project=$PROJECT_ID

echo -e "${GREEN}Workload Identity configured!${NC}"

# Output configuration
echo ""
echo -e "${GREEN}=== Configuration Summary ===${NC}"
echo ""
echo "Add these to your values.yaml:"
echo ""
echo "airflow:"
echo "  config:"
echo "    AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER: \"gs://$BUCKET_NAME/airflow/logs\""
echo ""
echo "serviceAccount:"
echo "  annotations:"
echo "    iam.gke.io/gcp-service-account: ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
echo ""
echo -e "${GREEN}Setup complete!${NC}"
