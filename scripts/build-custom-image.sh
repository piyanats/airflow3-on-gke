#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID="${GCP_PROJECT_ID:-}"
IMAGE_NAME="${IMAGE_NAME:-airflow-custom}"
IMAGE_TAG="${IMAGE_TAG:-3.0.0-v1}"
DOCKERFILE="${DOCKERFILE:-docker/Dockerfile}"
REGISTRY_TYPE="${REGISTRY_TYPE:-gcr}"  # gcr or artifact-registry
REGION="${GCP_REGION:-us-central1}"
PUSH_IMAGE="${PUSH_IMAGE:-true}"

echo -e "${GREEN}=== Building Custom Airflow Image ===${NC}"
echo ""

# Check prerequisites
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: docker is not installed${NC}"
    exit 1
fi

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

# Determine registry URL
if [ "$REGISTRY_TYPE" = "gcr" ]; then
    REGISTRY_URL="gcr.io"
    FULL_IMAGE_NAME="${REGISTRY_URL}/${PROJECT_ID}/${IMAGE_NAME}:${IMAGE_TAG}"
    CONFIGURE_CMD="gcloud auth configure-docker"
elif [ "$REGISTRY_TYPE" = "artifact-registry" ]; then
    REGISTRY_URL="${REGION}-docker.pkg.dev"
    REPO_NAME="${ARTIFACT_REPO_NAME:-airflow}"
    FULL_IMAGE_NAME="${REGISTRY_URL}/${PROJECT_ID}/${REPO_NAME}/${IMAGE_NAME}:${IMAGE_TAG}"
    CONFIGURE_CMD="gcloud auth configure-docker ${REGION}-docker.pkg.dev"
else
    echo -e "${RED}Error: Invalid REGISTRY_TYPE. Use 'gcr' or 'artifact-registry'${NC}"
    exit 1
fi

echo "Configuration:"
echo "  Project ID: $PROJECT_ID"
echo "  Image Name: $IMAGE_NAME"
echo "  Image Tag: $IMAGE_TAG"
echo "  Dockerfile: $DOCKERFILE"
echo "  Registry: $REGISTRY_TYPE"
echo "  Full Image: $FULL_IMAGE_NAME"
echo ""

# Check if Dockerfile exists
if [ ! -f "$DOCKERFILE" ]; then
    echo -e "${RED}Error: Dockerfile not found at $DOCKERFILE${NC}"
    exit 1
fi

# Check if requirements.txt exists
REQUIREMENTS_FILE="docker/requirements.txt"
if [ ! -f "$REQUIREMENTS_FILE" ]; then
    echo -e "${YELLOW}Warning: requirements.txt not found at $REQUIREMENTS_FILE${NC}"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

read -p "Continue with build? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Build cancelled."
    exit 0
fi

# Build the image
echo -e "${YELLOW}>>> Building Docker image...${NC}"
docker build \
    -f "$DOCKERFILE" \
    -t "$FULL_IMAGE_NAME" \
    -t "${IMAGE_NAME}:${IMAGE_TAG}" \
    -t "${IMAGE_NAME}:latest" \
    docker/

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Image built successfully${NC}"
else
    echo -e "${RED}✗ Image build failed${NC}"
    exit 1
fi

# Show image size
echo ""
echo "Image size:"
docker images | grep "$IMAGE_NAME" | head -1

# Test the image
echo ""
read -p "Run basic tests on the image? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}>>> Testing image...${NC}"

    # Test Python version
    echo "Testing Python version:"
    docker run --rm "$FULL_IMAGE_NAME" python --version

    # Test pip list
    echo ""
    echo "Installed packages:"
    docker run --rm "$FULL_IMAGE_NAME" pip list | head -20

    # Test imports
    echo ""
    echo "Testing imports:"
    docker run --rm "$FULL_IMAGE_NAME" python -c "import pandas; print(f'✓ pandas {pandas.__version__}')"
    docker run --rm "$FULL_IMAGE_NAME" python -c "import google.cloud.storage; print('✓ google-cloud-storage')" || true
    docker run --rm "$FULL_IMAGE_NAME" python -c "import requests; print('✓ requests')"

    # Test pip check
    echo ""
    echo "Checking for conflicts:"
    docker run --rm "$FULL_IMAGE_NAME" pip check
fi

# Push to registry
if [ "$PUSH_IMAGE" = "true" ]; then
    echo ""
    read -p "Push image to registry? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Configure Docker authentication
        echo -e "${YELLOW}>>> Configuring Docker authentication...${NC}"
        eval "$CONFIGURE_CMD"

        # Create Artifact Registry repository if needed
        if [ "$REGISTRY_TYPE" = "artifact-registry" ]; then
            echo -e "${YELLOW}>>> Ensuring Artifact Registry repository exists...${NC}"
            gcloud artifacts repositories create "$REPO_NAME" \
                --repository-format=docker \
                --location="$REGION" \
                --description="Airflow custom images" \
                --project="$PROJECT_ID" 2>/dev/null || \
                echo "Repository already exists or creation failed"
        fi

        # Push the image
        echo -e "${YELLOW}>>> Pushing image to registry...${NC}"
        docker push "$FULL_IMAGE_NAME"

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Image pushed successfully${NC}"
        else
            echo -e "${RED}✗ Image push failed${NC}"
            exit 1
        fi
    fi
fi

# Output summary
echo ""
echo -e "${GREEN}=== Build Complete ===${NC}"
echo ""
echo "Image: $FULL_IMAGE_NAME"
echo ""
echo "To use this image, update your values.yaml:"
echo ""
echo "airflow:"
echo "  image:"
echo "    repository: ${FULL_IMAGE_NAME%:*}"
echo "    tag: \"${IMAGE_TAG}\""
echo "    pullPolicy: IfNotPresent"
echo ""
echo "Then deploy:"
echo "  helm upgrade --install airflow ./airflow-helm -f your-values.yaml"
echo ""

# Optional: Save configuration
CONFIG_FILE="docker/build-config.txt"
cat > "$CONFIG_FILE" <<EOF
Build Configuration
===================
Date: $(date)
Project ID: $PROJECT_ID
Image: $FULL_IMAGE_NAME
Dockerfile: $DOCKERFILE
Registry: $REGISTRY_TYPE
EOF

echo "Build configuration saved to: $CONFIG_FILE"
echo ""

# Optional: Generate values file
read -p "Generate example values file? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    VALUES_FILE="examples/values-custom-image.yaml"
    cat > "$VALUES_FILE" <<EOF
# Airflow configuration with custom image
# Generated on $(date)

airflow:
  version: "3.0.0"
  image:
    repository: ${FULL_IMAGE_NAME%:*}
    tag: "${IMAGE_TAG}"
    pullPolicy: IfNotPresent

  config:
    AIRFLOW__CORE__EXECUTOR: KubernetesExecutor
    AIRFLOW__CORE__LOAD_EXAMPLES: "False"

webserver:
  replicas: 2
  resources:
    requests:
      cpu: "1000m"
      memory: "2Gi"
    limits:
      cpu: "2000m"
      memory: "4Gi"

scheduler:
  replicas: 2
  resources:
    requests:
      cpu: "1000m"
      memory: "2Gi"
    limits:
      cpu: "2000m"
      memory: "4Gi"

postgresql:
  enabled: true
  persistence:
    enabled: true
    size: 10Gi

dags:
  persistence:
    enabled: true
    size: 5Gi

rbac:
  create: true
EOF

    echo -e "${GREEN}Values file generated: $VALUES_FILE${NC}"
fi

echo ""
echo -e "${GREEN}Done!${NC}"
