#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-airflow-cluster}"
ZONE="${GCP_ZONE:-us-central1-a}"
NAMESPACE="${NAMESPACE:-default}"
RELEASE_NAME="${RELEASE_NAME:-airflow}"
DELETE_CLUSTER="${DELETE_CLUSTER:-false}"

echo -e "${YELLOW}=== Apache Airflow 3 Uninstallation ===${NC}"
echo ""
echo "Namespace: $NAMESPACE"
echo "Release Name: $RELEASE_NAME"
echo ""

# Ask for confirmation
read -p "Do you want to uninstall Airflow? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstallation cancelled."
    exit 0
fi

# Uninstall Helm release
echo -e "${YELLOW}>>> Uninstalling Helm release...${NC}"
helm uninstall $RELEASE_NAME -n $NAMESPACE || true

echo -e "${GREEN}Airflow uninstalled!${NC}"

# Delete PVCs
echo -e "${YELLOW}>>> Deleting PersistentVolumeClaims...${NC}"
kubectl delete pvc -n $NAMESPACE -l app=airflow --wait=false || true
kubectl delete pvc -n $NAMESPACE postgres-pvc --wait=false || true

echo ""
read -p "Do you want to delete the GKE cluster? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}>>> Deleting GKE cluster...${NC}"
    gcloud container clusters delete $CLUSTER_NAME \
        --zone=$ZONE \
        --quiet || true
    echo -e "${GREEN}Cluster deleted!${NC}"
fi

echo ""
echo -e "${GREEN}=== Uninstallation Complete! ===${NC}"
