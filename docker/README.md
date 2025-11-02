# Custom Airflow Docker Image

This directory contains files for building a custom Apache Airflow image with additional dependencies.

## Files

- **Dockerfile** - Main Dockerfile with system and Python dependencies
- **Dockerfile.slim** - Lightweight version with only Python packages
- **Dockerfile.multi-stage** - Multi-stage build for optimized image size
- **requirements.txt** - Python dependencies
- **requirements-minimal.txt** - Minimal example

## Quick Start

### 1. Edit requirements.txt

Add your Python dependencies:

```txt
pandas==2.1.4
google-cloud-storage==2.13.0
your-package==1.0.0
```

### 2. Build the image

Using the build script:

```bash
cd ..
export GCP_PROJECT_ID="your-project-id"
export IMAGE_NAME="airflow-custom"
export IMAGE_TAG="3.0.0-v1"

./scripts/build-custom-image.sh
```

Or manually:

```bash
# Build
docker build -t gcr.io/your-project/airflow-custom:3.0.0-v1 -f Dockerfile .

# Push to GCR
gcloud auth configure-docker
docker push gcr.io/your-project/airflow-custom:3.0.0-v1
```

### 3. Use in Helm

```yaml
airflow:
  image:
    repository: gcr.io/your-project/airflow-custom
    tag: "3.0.0-v1"
```

## Dockerfile Variants

### Standard (Dockerfile)
- Includes system dependencies (gcc, build tools)
- Best for packages that need compilation
- Larger image size but more compatible

### Slim (Dockerfile.slim)
- Only Python packages
- Faster builds
- Smaller image size
- Use when you don't need system packages

### Multi-stage (Dockerfile.multi-stage)
- Compiles packages in builder stage
- Copies only wheels to final image
- Smallest final image size
- Best for production

## Testing Locally

```bash
# Build
docker build -t airflow-test .

# Test imports
docker run --rm airflow-test python -c "import pandas; print(pandas.__version__)"

# Interactive shell
docker run -it --rm airflow-test bash

# Run Airflow webserver
docker run -it --rm -p 8080:8080 \
    -e AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=sqlite:////tmp/airflow.db \
    airflow-test \
    bash -c "airflow db init && airflow webserver"
```

## Best Practices

1. **Pin all versions** in requirements.txt
2. **Use multi-stage builds** for production
3. **Minimize layers** by combining RUN commands
4. **Don't include DAGs** in the image (use Git-Sync or PVC)
5. **Scan for vulnerabilities** before pushing
6. **Tag with version numbers** for reproducibility

## Security Scanning

```bash
# Using Trivy
trivy image gcr.io/your-project/airflow-custom:3.0.0-v1

# Using Google Container Analysis
gcloud container images scan gcr.io/your-project/airflow-custom:3.0.0-v1
```

## CI/CD Integration

See `docs/CUSTOM_DEPENDENCIES.md` for GitHub Actions and Cloud Build examples.

## Troubleshooting

### Build fails with "No space left on device"

```bash
docker system prune -a
```

### Package conflicts

```bash
docker run --rm your-image pip check
```

### Import errors

Check that package is in requirements.txt and rebuild.

## Resources

- [Complete Guide](../docs/CUSTOM_DEPENDENCIES.md)
- [Airflow Docker Docs](https://airflow.apache.org/docs/docker-stack/build.html)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
