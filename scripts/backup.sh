#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

NAMESPACE="${NAMESPACE:-default}"
RELEASE_NAME="${RELEASE_NAME:-airflow}"
BACKUP_DIR="./backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo -e "${GREEN}=== Airflow Backup ===${NC}"
echo ""

# Create backup directory
mkdir -p $BACKUP_DIR

# Backup 1: Helm values
echo -e "${YELLOW}>>> Backing up Helm values...${NC}"
helm get values $RELEASE_NAME -n $NAMESPACE > $BACKUP_DIR/values-$TIMESTAMP.yaml
check_status "Helm values backup"

# Backup 2: Kubernetes resources
echo -e "${YELLOW}>>> Backing up Kubernetes resources...${NC}"
kubectl get all -n $NAMESPACE -l app=airflow -o yaml > $BACKUP_DIR/k8s-resources-$TIMESTAMP.yaml
check_status "Kubernetes resources backup"

# Backup 3: ConfigMaps and Secrets
echo -e "${YELLOW}>>> Backing up ConfigMaps...${NC}"
kubectl get configmap -n $NAMESPACE -l app=airflow -o yaml > $BACKUP_DIR/configmaps-$TIMESTAMP.yaml
check_status "ConfigMaps backup"

# Backup 4: DAGs (if using persistent volume)
echo -e "${YELLOW}>>> Backing up DAGs...${NC}"
POD_NAME=$(kubectl get pods -n $NAMESPACE -l component=webserver -o jsonpath='{.items[0].metadata.name}')
if [ -n "$POD_NAME" ]; then
    kubectl exec -n $NAMESPACE $POD_NAME -- tar czf /tmp/dags-backup.tar.gz -C /opt/airflow dags 2>/dev/null || true
    kubectl cp $NAMESPACE/$POD_NAME:/tmp/dags-backup.tar.gz $BACKUP_DIR/dags-$TIMESTAMP.tar.gz 2>/dev/null || \
        echo -e "${YELLOW}⚠ Could not backup DAGs${NC}"
fi

# Backup 5: Database (if using PostgreSQL pod)
if kubectl get deployment postgres -n $NAMESPACE &>/dev/null; then
    echo -e "${YELLOW}>>> Backing up database...${NC}"
    kubectl exec -n $NAMESPACE deployment/postgres -- \
        pg_dump -U airflow airflow > $BACKUP_DIR/database-$TIMESTAMP.sql 2>/dev/null || \
        echo -e "${YELLOW}⚠ Could not backup database${NC}"
fi

# Create archive
echo -e "${YELLOW}>>> Creating backup archive...${NC}"
tar czf $BACKUP_DIR/airflow-backup-$TIMESTAMP.tar.gz -C $BACKUP_DIR \
    values-$TIMESTAMP.yaml \
    k8s-resources-$TIMESTAMP.yaml \
    configmaps-$TIMESTAMP.yaml \
    2>/dev/null

# Clean up individual files
rm -f $BACKUP_DIR/values-$TIMESTAMP.yaml \
      $BACKUP_DIR/k8s-resources-$TIMESTAMP.yaml \
      $BACKUP_DIR/configmaps-$TIMESTAMP.yaml

echo ""
echo -e "${GREEN}=== Backup Complete ===${NC}"
echo ""
echo "Backup location: $BACKUP_DIR/airflow-backup-$TIMESTAMP.tar.gz"
echo ""
echo "To restore:"
echo "  tar xzf $BACKUP_DIR/airflow-backup-$TIMESTAMP.tar.gz -C /tmp"
echo "  helm upgrade $RELEASE_NAME ./airflow-helm -n $NAMESPACE -f /tmp/values-$TIMESTAMP.yaml"
echo ""

# Function to check status
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $1${NC}"
    else
        echo -e "${RED}✗ $1${NC}"
    fi
}
