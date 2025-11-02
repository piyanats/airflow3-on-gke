#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

NAMESPACE="${NAMESPACE:-default}"
RELEASE_NAME="${RELEASE_NAME:-airflow}"

echo -e "${GREEN}=== Testing Airflow Deployment ===${NC}"
echo ""

# Function to check command status
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $1${NC}"
        return 0
    else
        echo -e "${RED}✗ $1${NC}"
        return 1
    fi
}

# Test 1: Check if pods are running
echo -e "${YELLOW}>>> Checking if pods are running...${NC}"
WEBSERVER_PODS=$(kubectl get pods -n $NAMESPACE -l component=webserver --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
SCHEDULER_PODS=$(kubectl get pods -n $NAMESPACE -l component=scheduler --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

if [ "$WEBSERVER_PODS" -gt 0 ]; then
    echo -e "${GREEN}✓ Webserver pods running: $WEBSERVER_PODS${NC}"
else
    echo -e "${RED}✗ No webserver pods running${NC}"
fi

if [ "$SCHEDULER_PODS" -gt 0 ]; then
    echo -e "${GREEN}✓ Scheduler pods running: $SCHEDULER_PODS${NC}"
else
    echo -e "${RED}✗ No scheduler pods running${NC}"
fi

# Test 2: Check database connection
echo ""
echo -e "${YELLOW}>>> Testing database connection...${NC}"
kubectl exec -n $NAMESPACE deployment/${RELEASE_NAME}-webserver -- airflow db check 2>/dev/null
check_status "Database connection"

# Test 3: Check if webserver is accessible
echo ""
echo -e "${YELLOW}>>> Testing webserver health endpoint...${NC}"
POD_NAME=$(kubectl get pods -n $NAMESPACE -l component=webserver -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$POD_NAME" ]; then
    kubectl exec -n $NAMESPACE $POD_NAME -- curl -s http://localhost:8080/health > /dev/null 2>&1
    check_status "Webserver health endpoint"
else
    echo -e "${RED}✗ Could not find webserver pod${NC}"
fi

# Test 4: List DAGs
echo ""
echo -e "${YELLOW}>>> Listing DAGs...${NC}"
DAGS=$(kubectl exec -n $NAMESPACE deployment/${RELEASE_NAME}-webserver -- airflow dags list 2>/dev/null)
if [ -n "$DAGS" ]; then
    echo -e "${GREEN}✓ DAGs found:${NC}"
    echo "$DAGS"
else
    echo -e "${YELLOW}⚠ No DAGs found${NC}"
fi

# Test 5: Check service endpoints
echo ""
echo -e "${YELLOW}>>> Checking service endpoints...${NC}"
kubectl get endpoints -n $NAMESPACE ${RELEASE_NAME}-webserver 2>/dev/null
check_status "Service endpoints"

# Test 6: Check persistent volumes
echo ""
echo -e "${YELLOW}>>> Checking persistent volumes...${NC}"
kubectl get pvc -n $NAMESPACE 2>/dev/null
check_status "Persistent volumes"

# Test 7: Check resource usage
echo ""
echo -e "${YELLOW}>>> Checking resource usage...${NC}"
kubectl top pods -n $NAMESPACE -l app=airflow 2>/dev/null || \
    echo -e "${YELLOW}⚠ Metrics server not available${NC}"

# Summary
echo ""
echo -e "${GREEN}=== Test Summary ===${NC}"
echo ""

# Get service info
echo "Service Information:"
kubectl get service ${RELEASE_NAME}-webserver -n $NAMESPACE 2>/dev/null

echo ""
echo "To access Airflow UI:"
echo "  kubectl port-forward -n $NAMESPACE svc/${RELEASE_NAME}-webserver 8080:8080"
echo ""

# Check for issues
FAILED_PODS=$(kubectl get pods -n $NAMESPACE -l app=airflow --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l)
if [ "$FAILED_PODS" -gt 0 ]; then
    echo -e "${YELLOW}⚠ Warning: $FAILED_PODS pod(s) not in Running state${NC}"
    kubectl get pods -n $NAMESPACE -l app=airflow --field-selector=status.phase!=Running 2>/dev/null
else
    echo -e "${GREEN}✓ All pods are running${NC}"
fi

echo ""
echo -e "${GREEN}Testing complete!${NC}"
