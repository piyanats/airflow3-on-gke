#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="${NAMESPACE:-default}"
RELEASE_NAME="${RELEASE_NAME:-airflow}"

echo -e "${GREEN}=== Apache Airflow Upgrade ===${NC}"
echo ""

# Upgrade Airflow using Helm
echo -e "${YELLOW}>>> Upgrading Apache Airflow...${NC}"
helm upgrade $RELEASE_NAME ./airflow-helm \
    --namespace=$NAMESPACE \
    --reuse-values \
    --wait \
    --timeout=10m

echo -e "${GREEN}Upgrade completed!${NC}"
echo ""

# Show rollout status
echo -e "${YELLOW}>>> Checking deployment status...${NC}"
kubectl rollout status deployment/${RELEASE_NAME}-webserver -n $NAMESPACE
kubectl rollout status deployment/${RELEASE_NAME}-scheduler -n $NAMESPACE

echo ""
echo -e "${GREEN}All deployments are ready!${NC}"
