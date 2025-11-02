# Quick Setup Guide: Custom Dependencies

## คู่มือติดตั้ง Python Packages เพิ่มเติมแบบด่วน

### วิธีที่ 1: สร้าง Custom Docker Image (แนะนำ) 🚀

#### ขั้นตอนที่ 1: เพิ่ม Dependencies

แก้ไขไฟล์ `docker/requirements.txt`:

```txt
# เพิ่ม packages ที่ต้องการ
pandas==2.1.4
google-cloud-storage==2.13.0
google-cloud-bigquery==3.14.0
requests==2.31.0
```

#### ขั้นตอนที่ 2: Build Image

```bash
# ตั้งค่า environment variables
export GCP_PROJECT_ID="your-project-id"
export IMAGE_NAME="airflow-custom"
export IMAGE_TAG="3.0.0-v1"

# Build และ push
./scripts/build-custom-image.sh
```

Script จะทำให้อัตโนมัติ:
- Build Docker image
- Test imports
- Push to Google Container Registry
- สร้างไฟล์ values.yaml ตัวอย่าง

#### ขั้นตอนที่ 3: Deploy

```bash
helm upgrade --install airflow ./airflow-helm \
    -f examples/values-custom-image.yaml
```

### วิธีที่ 2: ใช้ Init Container (สำหรับ Testing)

เหมาะสำหรับทดสอบ packages ก่อน build image

```yaml
# values.yaml
airflow:
  extraInitContainers:
    - name: install-deps
      image: apache/airflow:3.0.0-python3.11
      command:
        - bash
        - -c
        - |
          pip install --user \
            pandas==2.1.4 \
            google-cloud-storage==2.13.0
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

⚠️ **ข้อจำกัด:**
- ช้ากว่า (ติดตั้งทุกครั้งที่ pod restart)
- ไม่เหมาะสำหรับ production

### วิธีที่ 3: requirements.txt จาก Git Repository

#### ขั้นตอนที่ 1: เพิ่ม requirements.txt ใน DAGs repo

```
your-dags-repo/
├── dags/
│   └── my_dag.py
└── requirements.txt
```

#### ขั้นตอนที่ 2: Configure Airflow

```yaml
# values.yaml
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
        - name: deps
          mountPath: /home/airflow/.local

  extraVolumes:
    - name: deps
      emptyDir: {}

  extraVolumeMounts:
    - name: deps
      mountPath: /home/airflow/.local

dags:
  gitSync:
    enabled: true
    repo: "https://github.com/your-org/airflow-dags.git"
```

## ตัวอย่าง Dependencies แยกตามประเภท

### สำหรับ Google Cloud Platform

```txt
google-cloud-storage==2.13.0
google-cloud-bigquery==3.14.0
google-cloud-pubsub==2.19.0
db-dtypes==1.1.1
```

### สำหรับ Data Processing

```txt
pandas==2.1.4
numpy==1.26.2
pyarrow==14.0.1
polars==0.20.2
```

### สำหรับ AWS

```txt
boto3==1.34.8
s3fs==2023.12.2
awswrangler==3.5.1
```

### สำหรับ Machine Learning

```txt
scikit-learn==1.3.2
tensorflow==2.15.0
torch==2.1.2
mlflow==2.9.2
```

## Build แบบ Manual

```bash
# 1. Build image
cd docker/
docker build -t gcr.io/PROJECT_ID/airflow-custom:v1 .

# 2. Test locally
docker run --rm gcr.io/PROJECT_ID/airflow-custom:v1 \
    python -c "import pandas; print(pandas.__version__)"

# 3. Configure Docker
gcloud auth configure-docker

# 4. Push
docker push gcr.io/PROJECT_ID/airflow-custom:v1

# 5. Update values.yaml
# airflow:
#   image:
#     repository: gcr.io/PROJECT_ID/airflow-custom
#     tag: "v1"

# 6. Deploy
helm upgrade --install airflow ./airflow-helm -f values.yaml
```

## เลือก Dockerfile

มี 3 แบบให้เลือก:

### 1. Dockerfile (Standard)
```bash
docker build -f docker/Dockerfile .
```
- มี system dependencies (gcc, build tools)
- ใช้เมื่อต้องการ compile packages
- ขนาดใหญ่กว่า

### 2. Dockerfile.slim
```bash
docker build -f docker/Dockerfile.slim .
```
- Python packages อย่างเดียว
- Build เร็ว, ขนาดเล็ก
- ใช้เมื่อไม่ต้องการ system packages

### 3. Dockerfile.multi-stage
```bash
docker build -f docker/Dockerfile.multi-stage .
```
- Compile ใน builder stage
- Image ขนาดเล็กที่สุด
- เหมาะสำหรับ production

## การทดสอบ

```bash
# Test Python version
docker run --rm your-image python --version

# Test package imports
docker run --rm your-image \
    python -c "import pandas, numpy; print('OK')"

# Test pip check
docker run --rm your-image pip check

# Interactive shell
docker run -it --rm your-image bash
```

## Troubleshooting

### ปัญหา: Build ช้า
**วิธีแก้:** ใช้ multi-stage build หรือ build cache

### ปัญหา: Import error หลัง deploy
**วิธีแก้:**
```bash
# ตรวจสอบว่า package ติดตั้งหรือยัง
kubectl exec -it deployment/airflow-webserver -- pip list | grep pandas

# ตรวจสอบ Python path
kubectl exec -it deployment/airflow-webserver -- python -c "import sys; print(sys.path)"
```

### ปัญหา: Package conflicts
**วิธีแก้:**
```bash
# Check conflicts
docker run --rm your-image pip check

# ใช้ pip-compile
pip install pip-tools
pip-compile requirements.in
```

### ปัญหา: Image ขนาดใหญ่เกินไป
**วิธีแก้:**
- ใช้ multi-stage build
- ลบ packages ที่ไม่จำเป็น
- ใช้ slim base image

## Best Practices

✅ **DO:**
- Pin ทุก version ใน requirements.txt
- ใช้ multi-stage builds สำหรับ production
- Test image ก่อน deploy
- ใช้ semantic versioning (v1, v2, v3)
- Scan vulnerabilities

❌ **DON'T:**
- ใส่ DAGs ใน image (ใช้ Git-Sync แทน)
- ใช้ `pip install` ใน DAGs
- Hardcode secrets ใน image
- ใช้ `latest` tag ใน production

## Quick Reference

```bash
# Build
./scripts/build-custom-image.sh

# Build specific Dockerfile
export DOCKERFILE=docker/Dockerfile.slim
./scripts/build-custom-image.sh

# Use Artifact Registry instead of GCR
export REGISTRY_TYPE=artifact-registry
./scripts/build-custom-image.sh

# Skip push (local testing)
export PUSH_IMAGE=false
./scripts/build-custom-image.sh
```

## CI/CD Integration

### GitHub Actions
```yaml
name: Build Airflow Image
on:
  push:
    paths:
      - 'docker/**'
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: ./scripts/build-custom-image.sh
```

### Cloud Build
```bash
gcloud builds submit --config cloudbuild.yaml docker/
```

## เอกสารเพิ่มเติม

- [Complete Guide](CUSTOM_DEPENDENCIES.md)
- [Dockerfile Examples](../docker/)
- [Airflow Docker Documentation](https://airflow.apache.org/docs/docker-stack/build.html)

## ขั้นตอนสำหรับ Production

1. ✅ Pin all package versions
2. ✅ Use multi-stage build
3. ✅ Scan for vulnerabilities
4. ✅ Test thoroughly
5. ✅ Use semantic versioning
6. ✅ Document custom packages
7. ✅ Set up CI/CD for auto-build
