# การติดตั้ง Custom Dependencies ใน Airflow

คู่มือนี้อธิบายวิธีการเพิ่ม Python packages และ system dependencies แบบ custom ลงใน Airflow deployment บน GKE

## ภาพรวมของวิธีการ

มีหลายวิธีในการเพิ่ม custom dependencies:

1. **Custom Docker Image** (แนะนำสำหรับ production)
2. **Init Containers กับ pip install**
3. **requirements.txt ผ่าน Git-Sync**
4. **Persistent Volume กับ packages**

## วิธีที่ 1: Custom Docker Image (แนะนำ) 🚀

### ขั้นตอนที่ 1: สร้าง Dockerfile

สร้าง Dockerfile แบบ custom จาก Apache Airflow:

```dockerfile
FROM apache/airflow:3.0.0-python3.12

# เปลี่ยนเป็น root เพื่อติดตั้ง system packages
USER root

# ติดตั้ง system dependencies (ถ้าจำเป็น)
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    libpq-dev \
    git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# เปลี่ยนกลับเป็น airflow user
USER airflow

# คัดลอก requirements.txt
COPY requirements.txt /tmp/requirements.txt

# ติดตั้ง Python dependencies
RUN pip install --no-cache-dir -r /tmp/requirements.txt
```

### ขั้นตอนที่ 2: สร้าง requirements.txt

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
```

### ขั้นตอนที่ 3: Build และ Push Image

ใช้ script ที่เตรียมไว้:

```bash
# ตั้งค่า variables
export GCP_PROJECT_ID="your-project-id"
export IMAGE_NAME="airflow-custom"
export IMAGE_TAG="3.0.0-custom-v1"

# Build และ push
./scripts/build-custom-image.sh
```

หรือแบบ manual:

```bash
# Build image
docker build -t gcr.io/$GCP_PROJECT_ID/airflow-custom:3.0.0-v1 .

# กำหนดค่า Docker สำหรับ GCR
gcloud auth configure-docker

# Push ไปยัง Google Container Registry
docker push gcr.io/$GCP_PROJECT_ID/airflow-custom:3.0.0-v1
```

### ขั้นตอนที่ 4: อัปเดต Helm Values

```yaml
airflow:
  image:
    repository: gcr.io/YOUR_PROJECT_ID/airflow-custom
    tag: "3.0.0-v1"
    pullPolicy: IfNotPresent
```

### ขั้นตอนที่ 5: Deploy

```bash
helm upgrade --install airflow ./airflow-helm \
    -f values-custom-image.yaml
```

## วิธีที่ 2: Init Container กับ pip install

สำหรับการทดสอบอย่างรวดเร็วหรือ dependencies ง่ายๆ:

```yaml
# values.yaml
airflow:
  extraInitContainers:
    - name: install-dependencies
      image: apache/airflow:3.0.0-python3.12
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

**ข้อจำกัด:**
- ⚠️ เวลาเริ่มต้นช้ากว่า
- ⚠️ ติดตั้ง dependencies ทุกครั้งที่ pod restart
- ⚠️ ไม่คงอยู่ข้าม pod restarts

## วิธีที่ 3: requirements.txt ใน Git Repository

### ขั้นตอนที่ 1: เพิ่ม requirements.txt ใน DAGs Repository

```
your-dags-repo/
├── dags/
│   ├── example_dag.py
│   └── my_dag.py
└── requirements.txt
```

### ขั้นตอนที่ 2: กำหนดค่า Git-Sync กับ pip install

```yaml
airflow:
  extraInitContainers:
    - name: install-requirements
      image: apache/airflow:3.0.0-python3.12
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

## ตัวอย่าง Dependencies ทั่วไป

### สำหรับ Google Cloud Platform

```txt
# requirements.txt สำหรับ GCP
google-cloud-storage==2.13.0
google-cloud-bigquery==3.14.0
google-cloud-pubsub==2.19.0
google-cloud-dataproc==5.9.0
db-dtypes==1.1.1  # สำหรับ BigQuery data types
```

### สำหรับ Data Science

```txt
# requirements.txt สำหรับ Data Science
pandas==2.1.4
numpy==1.26.2
scipy==1.11.4
scikit-learn==1.3.2
matplotlib==3.8.2
seaborn==0.13.0
```

### สำหรับ Machine Learning

```txt
# requirements.txt สำหรับ ML
tensorflow==2.15.0
torch==2.1.2
transformers==4.36.2
mlflow==2.9.2
```

## Best Practices

### 1. Pin Versions
```txt
# ดี ✅
pandas==2.1.4
numpy==1.26.2

# ไม่ดี ❌
pandas
numpy>=1.20
```

### 2. ใช้ requirements.txt Generator

```bash
# ใน development environment ของคุณ
pip freeze > requirements.txt

# หรือใช้ pip-tools
pip install pip-tools
pip-compile requirements.in -o requirements.txt
```

### 3. Layer Caching

สั่ง Dockerfile commands จากน้อยที่สุดไปหามากที่สุดในการเปลี่ยนแปลง:

```dockerfile
FROM apache/airflow:3.0.0-python3.12

# System packages (เปลี่ยนไม่บ่อย)
USER root
RUN apt-get update && apt-get install -y gcc && apt-get clean

# Python packages (เปลี่ยนบางครั้ง)
USER airflow
COPY requirements.txt /tmp/
RUN pip install -r /tmp/requirements.txt

# Application code (เปลี่ยนบ่อย)
COPY dags/ ${AIRFLOW_HOME}/dags/
```

### 4. Security Scanning

```bash
# สแกนช่องโหว่
trivy image gcr.io/$PROJECT_ID/airflow-custom:latest

# หรือใช้ Google Container Analysis
gcloud container images scan gcr.io/$PROJECT_ID/airflow-custom:latest
```

## การแก้ไขปัญหา

### ปัญหา: Package conflicts

```bash
# ตรวจสอบ packages ที่ติดตั้งใน running pod
kubectl exec -it deployment/airflow-webserver -- pip list

# ตรวจสอบ conflicts
kubectl exec -it deployment/airflow-webserver -- pip check
```

### ปัญหา: Import errors

```bash
# ทดสอบ imports
kubectl exec -it deployment/airflow-webserver -- python -c "import pandas; print(pandas.__version__)"
```

### ปัญหา: Image builds ช้า

วิธีแก้: ใช้ multi-stage builds และ layer caching

## การทดสอบ Custom Image ในเครื่อง

```bash
# Build image
docker build -t airflow-custom:test .

# รันในเครื่อง
docker run -it --rm \
    -p 8080:8080 \
    -e AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=sqlite:////tmp/airflow.db \
    airflow-custom:test \
    bash -c "airflow db init && airflow webserver"

# ทดสอบ package imports
docker run -it --rm airflow-custom:test python -c "import pandas; print(pandas.__version__)"
```

## ทรัพยากร

- [Airflow Docker Documentation](https://airflow.apache.org/docs/docker-stack/build.html)
- [Google Container Registry](https://cloud.google.com/container-registry/docs)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [คู่มือด่วน: Custom Dependencies](QUICK_CUSTOM_DEPS_SETUP.md)
