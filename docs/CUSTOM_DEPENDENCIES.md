# Installing Custom Dependencies in Airflow

This guide explains how to add custom Python packages and system dependencies to your Airflow deployment on GKE.

## Methods Overview

There are several ways to add custom dependencies:

1. **Custom Docker Image** (Recommended for production)
2. **Init Containers with pip install**
3. **requirements.txt via Git-Sync**
4. **Persistent Volume with packages**

## Method 1: Custom Docker Image (Recommended) 🚀

### Step 1: Create Dockerfile

Create a custom Dockerfile based on Apache Airflow:

```dockerfile
FROM apache/airflow:3.0.0-python3.11

# Switch to root to install system packages
USER root

# Install system dependencies (if needed)
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    libpq-dev \
    git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Switch back to airflow user
USER airflow

# Copy requirements.txt
COPY requirements.txt /tmp/requirements.txt

# Install Python dependencies
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# Copy custom plugins (optional)
# COPY --chown=airflow:root plugins/ ${AIRFLOW_HOME}/plugins/

# Copy custom DAGs (optional)
# COPY --chown=airflow:root dags/ ${AIRFLOW_HOME}/dags/
```

### Step 2: Create requirements.txt

```txt
# Data Processing
pandas==2.1.4
numpy==1.26.2
pyarrow==14.0.1

# Google Cloud
google-cloud-storage==2.13.0
google-cloud-bigquery==3.14.0
google-cloud-pubsub==2.19.0

# AWS
boto3==1.34.8
s3fs==2023.12.2

# Databases
psycopg2-binary==2.9.9
pymongo==4.6.1
redis==5.0.1

# HTTP/API
requests==2.31.0
httpx==0.26.0

# Data Validation
pydantic==2.5.3
great-expectations==0.18.8

# Utilities
python-dotenv==1.0.0
tenacity==8.2.3

# Monitoring
sentry-sdk==1.39.1
```

### Step 3: Build and Push Image

Using our provided script:

```bash
# Set variables
export GCP_PROJECT_ID="your-project-id"
export IMAGE_NAME="airflow-custom"
export IMAGE_TAG="3.0.0-custom-v1"

# Build and push
./scripts/build-custom-image.sh
```

Or manually:

```bash
# Build image
docker build -t gcr.io/$GCP_PROJECT_ID/airflow-custom:3.0.0-v1 .

# Configure Docker for GCR
gcloud auth configure-docker

# Push to Google Container Registry
docker push gcr.io/$GCP_PROJECT_ID/airflow-custom:3.0.0-v1

# Or use Artifact Registry
gcloud auth configure-docker us-central1-docker.pkg.dev
docker push us-central1-docker.pkg.dev/$GCP_PROJECT_ID/airflow/airflow-custom:3.0.0-v1
```

### Step 4: Update Helm Values

```yaml
airflow:
  image:
    repository: gcr.io/YOUR_PROJECT_ID/airflow-custom
    tag: "3.0.0-v1"
    pullPolicy: IfNotPresent
```

### Step 5: Deploy

```bash
helm upgrade --install airflow ./airflow-helm \
    -f values-custom-image.yaml
```

## Method 2: Init Container with pip install

For quick testing or simple dependencies:

```yaml
# values.yaml
airflow:
  extraInitContainers:
    - name: install-dependencies
      image: apache/airflow:3.0.0-python3.11
      command:
        - bash
        - -c
        - |
          pip install --user \
            pandas==2.1.4 \
            google-cloud-storage==2.13.0 \
            requests==2.31.0
      volumeMounts:
        - name: dependencies
          mountPath: /home/airflow/.local

  extraVolumes:
    - name: dependencies
      emptyDir: {}

  extraVolumeMounts:
    - name: dependencies
      mountPath: /home/airflow/.local
```

**Limitations:**
- ⚠️ Slower startup time
- ⚠️ Dependencies installed on every pod restart
- ⚠️ Not persistent across pod restarts

## Method 3: requirements.txt in Git Repository

### Step 1: Add requirements.txt to DAGs Repository

```
your-dags-repo/
├── dags/
│   ├── example_dag.py
│   └── my_dag.py
└── requirements.txt
```

### Step 2: Configure Git-Sync with pip install

```yaml
airflow:
  extraInitContainers:
    - name: install-requirements
      image: apache/airflow:3.0.0-python3.11
      command:
        - bash
        - -c
        - |
          if [ -f /dags/requirements.txt ]; then
            pip install --user -r /dags/requirements.txt
          fi
      volumeMounts:
        - name: dags
          mountPath: /dags
        - name: dependencies
          mountPath: /home/airflow/.local

  extraVolumes:
    - name: dependencies
      emptyDir: {}

  extraVolumeMounts:
    - name: dependencies
      mountPath: /home/airflow/.local

dags:
  gitSync:
    enabled: true
    repo: "https://github.com/your-org/airflow-dags.git"
    branch: "main"
```

## Method 4: Python Packages via PersistentVolume

For shared packages across all pods:

```yaml
airflow:
  extraVolumes:
    - name: python-packages
      persistentVolumeClaim:
        claimName: airflow-python-packages

  extraVolumeMounts:
    - name: python-packages
      mountPath: /opt/python-packages

  config:
    PYTHONPATH: "/opt/python-packages:$PYTHONPATH"
```

## Installing System Dependencies

### Using Custom Docker Image

```dockerfile
FROM apache/airflow:3.0.0-python3.11

USER root

# Install system packages
RUN apt-get update && apt-get install -y \
    # Database clients
    postgresql-client \
    mysql-client \
    # Utilities
    curl \
    wget \
    vim \
    # Build tools
    gcc \
    g++ \
    make \
    # Libraries
    libpq-dev \
    libssl-dev \
    libffi-dev \
    # Graphics/ML libraries
    libopenblas-dev \
    liblapack-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

USER airflow
```

## Common Dependencies Examples

### For Google Cloud Platform

```txt
# requirements.txt for GCP
google-cloud-storage==2.13.0
google-cloud-bigquery==3.14.0
google-cloud-pubsub==2.19.0
google-cloud-dataproc==5.9.0
google-cloud-composer==1.12.0
db-dtypes==1.1.1  # For BigQuery data types
```

### For AWS

```txt
# requirements.txt for AWS
boto3==1.34.8
botocore==1.34.8
s3fs==2023.12.2
awswrangler==3.5.1
```

### For Data Science

```txt
# requirements.txt for Data Science
pandas==2.1.4
numpy==1.26.2
scipy==1.11.4
scikit-learn==1.3.2
matplotlib==3.8.2
seaborn==0.13.0
jupyterlab==4.0.9
```

### For Machine Learning

```txt
# requirements.txt for ML
tensorflow==2.15.0
torch==2.1.2
transformers==4.36.2
mlflow==2.9.2
```

### For Spark

```txt
# requirements.txt for Spark
pyspark==3.5.0
findspark==2.0.1
```

## Multi-Stage Docker Build

For optimized image size:

```dockerfile
# Build stage
FROM apache/airflow:3.0.0-python3.11 AS builder

USER root
RUN apt-get update && apt-get install -y gcc g++ && apt-get clean

USER airflow
COPY requirements.txt /tmp/requirements.txt
RUN pip wheel --no-cache-dir --wheel-dir /tmp/wheels -r /tmp/requirements.txt

# Final stage
FROM apache/airflow:3.0.0-python3.11

USER airflow
COPY --from=builder /tmp/wheels /tmp/wheels
COPY requirements.txt /tmp/requirements.txt

RUN pip install --no-cache-dir --no-index --find-links=/tmp/wheels -r /tmp/requirements.txt \
    && rm -rf /tmp/wheels /tmp/requirements.txt
```

## Best Practices

### 1. Pin Versions
```txt
# Good ✅
pandas==2.1.4
numpy==1.26.2

# Bad ❌
pandas
numpy>=1.20
```

### 2. Use requirements.txt Generator

```bash
# In your development environment
pip freeze > requirements.txt

# Or use pip-tools
pip install pip-tools
pip-compile requirements.in -o requirements.txt
```

### 3. Layer Caching

Order Dockerfile commands from least to most frequently changed:

```dockerfile
FROM apache/airflow:3.0.0-python3.11

# System packages (rarely change)
USER root
RUN apt-get update && apt-get install -y gcc && apt-get clean

# Python packages (change occasionally)
USER airflow
COPY requirements.txt /tmp/
RUN pip install -r /tmp/requirements.txt

# Application code (change frequently)
COPY dags/ ${AIRFLOW_HOME}/dags/
```

### 4. Security Scanning

```bash
# Scan for vulnerabilities
trivy image gcr.io/$PROJECT_ID/airflow-custom:latest

# Or use Google Container Analysis
gcloud container images scan gcr.io/$PROJECT_ID/airflow-custom:latest
```

### 5. Image Versioning

Use semantic versioning:
```
airflow-custom:3.0.0-v1
airflow-custom:3.0.0-v2
airflow-custom:3.0.0-v3-hotfix
```

## CI/CD Integration

### GitHub Actions Example

```yaml
# .github/workflows/build-airflow-image.yml
name: Build Airflow Image

on:
  push:
    branches: [main]
    paths:
      - 'docker/Dockerfile'
      - 'docker/requirements.txt'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up Cloud SDK
        uses: google-github-actions/setup-gcloud@v1

      - name: Configure Docker
        run: gcloud auth configure-docker

      - name: Build and Push
        run: |
          docker build -t gcr.io/${{ secrets.GCP_PROJECT }}/airflow-custom:${{ github.sha }} .
          docker push gcr.io/${{ secrets.GCP_PROJECT }}/airflow-custom:${{ github.sha }}
```

### Cloud Build Example

```yaml
# cloudbuild.yaml
steps:
  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'build'
      - '-t'
      - 'gcr.io/$PROJECT_ID/airflow-custom:$SHORT_SHA'
      - '-f'
      - 'docker/Dockerfile'
      - '.'

  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'push'
      - 'gcr.io/$PROJECT_ID/airflow-custom:$SHORT_SHA'

images:
  - 'gcr.io/$PROJECT_ID/airflow-custom:$SHORT_SHA'
```

## Troubleshooting

### Issue: Package conflicts

```bash
# Check installed packages in running pod
kubectl exec -it deployment/airflow-webserver -- pip list

# Check conflicts
kubectl exec -it deployment/airflow-webserver -- pip check
```

### Issue: Import errors

```bash
# Test imports
kubectl exec -it deployment/airflow-webserver -- python -c "import pandas; print(pandas.__version__)"
```

### Issue: Slow image builds

Solution: Use multi-stage builds and layer caching

### Issue: Large image size

```bash
# Check image size
docker images | grep airflow-custom

# Use dive to analyze layers
dive gcr.io/$PROJECT_ID/airflow-custom:latest
```

## Testing Custom Image Locally

```bash
# Build image
docker build -t airflow-custom:test .

# Run locally
docker run -it --rm \
    -p 8080:8080 \
    -e AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=sqlite:////tmp/airflow.db \
    airflow-custom:test \
    bash -c "airflow db init && airflow webserver"

# Test package imports
docker run -it --rm airflow-custom:test python -c "import pandas; print(pandas.__version__)"
```

## Directory Structure

```
airflow-custom-image/
├── Dockerfile
├── requirements.txt
├── requirements-dev.txt (optional)
├── plugins/
│   └── custom_plugin.py
├── dags/
│   └── example_dag.py
├── scripts/
│   ├── build.sh
│   └── push.sh
└── tests/
    └── test_imports.py
```

## Resources

- [Airflow Docker Documentation](https://airflow.apache.org/docs/docker-stack/build.html)
- [Google Container Registry](https://cloud.google.com/container-registry/docs)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Python Package Security](https://pypi.org/project/safety/)
