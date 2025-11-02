#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID="${GCP_PROJECT_ID:-}"
CLUSTER_NAME="${CLUSTER_NAME:-airflow-cluster}"
REGION="${GCP_REGION:-us-central1}"
ZONE="${GCP_ZONE:-us-central1-a}"
NAMESPACE="${NAMESPACE:-default}"
RELEASE_NAME="${RELEASE_NAME:-airflow}"

echo -e "${GREEN}=== Apache Airflow 3 Installation on GKE ===${NC}"
echo ""

# Function to print section headers
print_header() {
    echo -e "${YELLOW}>>> $1${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
print_header "Checking prerequisites..."

if ! command_exists gcloud; then
    echo -e "${RED}Error: gcloud CLI is not installed${NC}"
    echo "Install from: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

if ! command_exists kubectl; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    echo "Install from: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

if ! command_exists helm; then
    echo -e "${RED}Error: helm is not installed${NC}"
    echo "Install from: https://helm.sh/docs/intro/install/"
    exit 1
fi

echo -e "${GREEN}All prerequisites are installed!${NC}"
echo ""

# Get GCP project ID if not set
if [ -z "$PROJECT_ID" ]; then
    print_header "Getting GCP project ID..."
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [ -z "$PROJECT_ID" ]; then
        echo -e "${RED}Error: GCP project ID is not set${NC}"
        echo "Set it using: export GCP_PROJECT_ID=your-project-id"
        echo "Or run: gcloud config set project your-project-id"
        exit 1
    fi
fi

echo "Using GCP Project: $PROJECT_ID"
echo "Cluster Name: $CLUSTER_NAME"
echo "Region: $REGION"
echo "Zone: $ZONE"
echo "Namespace: $NAMESPACE"
echo "Release Name: $RELEASE_NAME"
echo ""

# Ask for confirmation
read -p "Do you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

# Check if cluster exists
print_header "Checking if GKE cluster exists..."
if gcloud container clusters describe $CLUSTER_NAME --zone=$ZONE --project=$PROJECT_ID &>/dev/null; then
    echo -e "${GREEN}Cluster $CLUSTER_NAME already exists${NC}"
else
    print_header "Creating GKE cluster..."
    gcloud container clusters create $CLUSTER_NAME \
        --zone=$ZONE \
        --project=$PROJECT_ID \
        --num-nodes=3 \
        --machine-type=e2-standard-4 \
        --disk-size=50 \
        --enable-autorepair \
        --enable-autoupgrade \
        --enable-autoscaling \
        --min-nodes=3 \
        --max-nodes=10 \
        --addons=HorizontalPodAutoscaling,HttpLoadBalancing \
        --workload-pool=$PROJECT_ID.svc.id.goog

    echo -e "${GREEN}Cluster created successfully!${NC}"
fi

# Get cluster credentials
print_header "Getting cluster credentials..."
gcloud container clusters get-credentials $CLUSTER_NAME \
    --zone=$ZONE \
    --project=$PROJECT_ID

echo -e "${GREEN}Credentials obtained!${NC}"

# Create namespace if it doesn't exist
print_header "Creating namespace..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Install Airflow using Helm
print_header "Installing Apache Airflow 3 using Helm..."
helm upgrade --install $RELEASE_NAME ./airflow-helm \
    --namespace=$NAMESPACE \
    --create-namespace \
    --wait \
    --timeout=10m

echo -e "${GREEN}Airflow installation completed!${NC}"
echo ""

# Wait for pods to be ready
print_header "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod \
    -l app=airflow \
    -n $NAMESPACE \
    --timeout=10m || true

# Get service information
print_header "Getting service information..."
echo ""
echo "Airflow Webserver Service:"
kubectl get service ${RELEASE_NAME}-webserver -n $NAMESPACE

echo ""
echo "All Pods:"
kubectl get pods -n $NAMESPACE

echo ""
echo -e "${GREEN}=== Installation Complete! ===${NC}"
echo ""
echo "To access Airflow UI:"
echo "1. Get the external IP:"
echo "   kubectl get service ${RELEASE_NAME}-webserver -n $NAMESPACE"
echo ""
echo "2. Or use port-forward:"
echo "   kubectl port-forward -n $NAMESPACE svc/${RELEASE_NAME}-webserver 8080:8080"
echo "   Then visit: http://localhost:8080"
echo ""
echo "Default credentials:"
echo "   Username: admin"
echo "   Password: admin"
echo ""
echo "To view logs:"
echo "   kubectl logs -n $NAMESPACE -l component=webserver"
echo "   kubectl logs -n $NAMESPACE -l component=scheduler"
echo ""
echo "To uninstall:"
echo "   helm uninstall $RELEASE_NAME -n $NAMESPACE"
echo ""
