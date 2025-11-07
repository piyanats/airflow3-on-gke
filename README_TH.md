# Apache Airflow 3 บน Google Kubernetes Engine (GKE)

คู่มือฉบับสมบูรณ์สำหรับการ Deploy Apache Airflow 3 บน GKE พร้อมกับ Workload Identity, Custom Docker images, และแนวทางปฏิบัติที่ดีที่สุดสำหรับ Production

[English Documentation](./README.md) | **[เอกสารภาษาไทย](./README_TH.md)**

---

## 📋 สารบัญ

- [ภาพรวม](#ภาพรวม)
- [คุณสมบัติหลัก](#คุณสมบัติหลัก)
- [ข้อกำหนดเบื้องต้น](#ข้อกำหนดเบื้องต้น)
- [เริ่มต้นอย่างรวดเร็ว](#เริ่มต้นอย่างรวดเร็ว)
- [โครงสร้างโปรเจกต์](#โครงสร้างโปรเจกต์)
- [การติดตั้งแบบละเอียด](#การติดตั้งแบบละเอียด)
- [Workload Identity](#workload-identity)
- [Custom Docker Images](#custom-docker-images)
- [การตั้งค่า Production](#การตั้งค่า-production)
- [การแก้ไขปัญหา](#การแก้ไขปัญหา)
- [การสนับสนุน](#การสนับสนุน)

---

## ภาพรวม

โปรเจกต์นี้จัดเตรียมวิธีที่ครบถ้วนในการ deploy **Apache Airflow 3.1.2** บน **Google Kubernetes Engine (GKE)** พร้อมกับ:

- ✅ **Workload Identity** สำหรับการเข้าถึง GCP อย่างปลอดภัย
- ✅ **Custom Docker images** พร้อม dependencies เพิ่มเติม
- ✅ **UV package manager** (เร็วกว่า pip 10-100 เท่า)
- ✅ **Helm charts** ที่พร้อมใช้งานใน production
- ✅ **การตั้งค่าตัวอย่างหลายแบบ** (Production, Cloud SQL, External DB)
- ✅ **Security best practices** ตามมาตรฐาน GCP
- ✅ **เอกสารครบถ้วน** ทั้งภาษาไทยและอังกฤษ

---

## คุณสมบัติหลัก

### 🚀 Apache Airflow 3.1.2
- เวอร์ชันล่าสุดพร้อมฟีเจอร์ใหม่ทั้งหมด
- KubernetesExecutor สำหรับการ scale แบบ dynamic
- UI ที่ออกแบบใหม่ด้วย React
- DAG Versioning และ Event-Driven Scheduling

### 🔐 Workload Identity
- **Keyless authentication**: ไม่ต้องใช้ service account JSON keys
- **Auto-rotating credentials**: หมุนเวียน credentials อัตโนมัติ
- **Fine-grained permissions**: ควบคุมสิทธิ์ได้ละเอียด
- **Audit logging**: ติดตามการเข้าถึงได้ครบถ้วน

### 📦 Custom Dependencies
รวม Python packages ยอดนิยม:
- **Google Cloud**: `google-cloud-storage` 3.5.0, `google-cloud-bigquery` 3.38.0
- **Data Processing**: `pandas` 2.3.3, `numpy` 2.3.4, `polars` 1.35.1, `pyarrow` 19.0.1
- **HTTP Clients**: `requests` 2.32.5, `httpx` 0.28.1, `aiohttp` 3.13.2
- **Validation**: `pydantic` 2.12.4

### ⚡ UV Package Manager
- เร็วกว่า pip 10-100 เท่า (เขียนด้วย Rust)
- รองรับใน Dockerfile 4 แบบ
- จัดการ dependencies ได้ดีกว่า

### 📊 Helm Charts
- พร้อมใช้งานใน production
- รองรับ High Availability (HA)
- Autoscaling configuration
- Pod Disruption Budgets

---

## ข้อกำหนดเบื้องต้น

### เครื่องมือที่ต้องมี
- **Google Cloud account** พร้อม billing เปิดใช้งาน
- **gcloud CLI** ติดตั้งและตั้งค่าแล้ว
- **kubectl** สำหรับจัดการ Kubernetes
- **Helm 3.x** สำหรับ deploy charts
- **Docker** (สำหรับ build custom images)

### GCP APIs ที่ต้องเปิดใช้งาน
```bash
gcloud services enable \
    container.googleapis.com \
    compute.googleapis.com \
    storage.googleapis.com \
    cloudresourcemanager.googleapis.com \
    iam.googleapis.com
```

---

## เริ่มต้นอย่างรวดเร็ว

### วิธีที่ 1: การติดตั้งแบบอัตโนมัติ (แนะนำ)

```bash
# 1. Clone repository
git clone https://github.com/piyanats/airflow3-on-gke.git
cd airflow3-on-gke

# 2. ตั้งค่าตัวแปร environment
export GCP_PROJECT_ID="your-project-id"
export CLUSTER_NAME="airflow-cluster"
export ZONE="asia-southeast1-a"

# 3. รัน installation script
chmod +x install.sh
./install.sh

# 4. ตั้งค่า Workload Identity
export NAMESPACE="default"
./scripts/create-gcp-resources.sh

# 5. อัพเดท values.yaml ด้วย project ID ของคุณ
sed -i "s/YOUR-PROJECT-ID/${GCP_PROJECT_ID}/g" airflow-helm/values.yaml

# 6. Deploy Airflow
helm install airflow ./airflow-helm -f airflow-helm/values.yaml

# 7. รอจนพร้อมใช้งาน
kubectl wait --for=condition=ready pod -l app=airflow --timeout=300s

# 8. เข้าถึง Airflow UI
kubectl port-forward svc/airflow-webserver 8080:8080
# เปิดเบราว์เซอร์: http://localhost:8080
# Username: admin
# Password: admin
```

### วิธีที่ 2: การติดตั้งแบบทีละขั้นตอน

ดูคำแนะนำละเอียดใน [การติดตั้งแบบละเอียด](#การติดตั้งแบบละเอียด)

---

## โครงสร้างโปรเจกต์

```
airflow3-on-gke/
├── airflow-helm/              # Helm chart สำหรับ Airflow
│   ├── Chart.yaml             # Chart metadata
│   ├── values.yaml            # ค่าตั้งต้น (Workload Identity enabled)
│   └── templates/             # Kubernetes manifests
│       ├── deployment-webserver.yaml
│       ├── deployment-scheduler.yaml
│       ├── serviceaccount.yaml
│       └── ...
├── docker/                    # Custom Docker images
│   ├── Dockerfile             # Image หลักพร้อม UV
│   ├── Dockerfile.multi-stage # Multi-stage build
│   ├── Dockerfile.uv-fast     # Ultra-fast build
│   ├── Dockerfile.slim        # Minimal image
│   ├── requirements.txt       # Python dependencies (ล่าสุด 2025)
│   └── cloudbuild.yaml        # Cloud Build configuration
├── examples/                  # ตัวอย่างการตั้งค่า
│   ├── values-production.yaml # Production-ready config
│   ├── values-cloudsql.yaml   # Cloud SQL integration
│   ├── values-external-db.yaml # External database
│   ├── values-custom.yaml     # Custom configuration
│   ├── WORKLOAD_IDENTITY_SETUP.md    # คู่มือภาษาอังกฤษ
│   └── WORKLOAD_IDENTITY_SETUP_TH.md # คู่มือภาษาไทย
├── scripts/                   # Helper scripts
│   ├── create-gcp-resources.sh # ตั้งค่า Workload Identity
│   └── cleanup.sh             # ลบทรัพยากรทั้งหมด
├── install.sh                 # Installation script อัตโนมัติ
├── README.md                  # เอกสารภาษาอังกฤษ
└── README_TH.md              # เอกสารภาษาไทย (ไฟล์นี้)
```

---

## การติดตั้งแบบละเอียด

### ขั้นตอนที่ 1: สร้าง GKE Cluster

```bash
# ตั้งค่าตัวแปร
export GCP_PROJECT_ID="your-project-id"
export CLUSTER_NAME="airflow-cluster"
export ZONE="asia-southeast1-a"

# สร้าง cluster พร้อม Workload Identity
gcloud container clusters create $CLUSTER_NAME \
    --zone=$ZONE \
    --project=$GCP_PROJECT_ID \
    --num-nodes=3 \
    --machine-type=e2-standard-4 \
    --disk-size=50 \
    --enable-autorepair \
    --enable-autoupgrade \
    --enable-autoscaling \
    --min-nodes=3 \
    --max-nodes=10 \
    --workload-pool=$GCP_PROJECT_ID.svc.id.goog

# เชื่อมต่อกับ cluster
gcloud container clusters get-credentials $CLUSTER_NAME \
    --zone=$ZONE \
    --project=$GCP_PROJECT_ID
```

### ขั้นตอนที่ 2: ตั้งค่า Workload Identity

**วิธีที่ A: ใช้ Script อัตโนมัติ (แนะนำ)**

```bash
export GCP_PROJECT_ID="your-project-id"
export NAMESPACE="default"
./scripts/create-gcp-resources.sh
```

**วิธีที่ B: ตั้งค่าด้วยตนเอง**

```bash
# 1. สร้าง GCP service account
gcloud iam service-accounts create airflow-sa \
    --display-name="Airflow Service Account" \
    --project=$GCP_PROJECT_ID

# 2. มอบสิทธิ์ (ตัวอย่าง: GCS storage)
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
    --member="serviceAccount:airflow-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/storage.admin"

# 3. สร้าง Workload Identity binding
gcloud iam service-accounts add-iam-policy-binding \
    airflow-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:${GCP_PROJECT_ID}.svc.id.goog[default/airflow]" \
    --project=$GCP_PROJECT_ID
```

**ดูรายละเอียดเพิ่มเติม**: [คู่มือ Workload Identity ภาษาไทย](./examples/WORKLOAD_IDENTITY_SETUP_TH.md)

### ขั้นตอนที่ 3: อัพเดท Values Configuration

```bash
# อัพเดท project ID ใน values.yaml
sed -i "s/YOUR-PROJECT-ID/${GCP_PROJECT_ID}/g" airflow-helm/values.yaml

# หรือแก้ไขด้วยมือ
nano airflow-helm/values.yaml
```

ตรวจสอบว่า annotation ถูกต้อง:
```yaml
serviceAccount:
  create: true
  name: "airflow"
  annotations:
    iam.gke.io/gcp-service-account: airflow-sa@your-project-id.iam.gserviceaccount.com
```

### ขั้นตอนที่ 4: Deploy Airflow

```bash
# ติดตั้ง Airflow ด้วย Helm
helm install airflow ./airflow-helm -f airflow-helm/values.yaml

# ตรวจสอบสถานะ
kubectl get pods -n default

# รอจน pods พร้อม
kubectl wait --for=condition=ready pod -l app=airflow --timeout=300s
```

### ขั้นตอนที่ 5: เข้าถึง Airflow UI

**วิธีที่ A: Port Forward (Development)**

```bash
kubectl port-forward svc/airflow-webserver 8080:8080
```

เปิดเบราว์เซอร์: http://localhost:8080
- Username: `admin`
- Password: `admin`

**วิธีที่ B: LoadBalancer (Production)**

ดู External IP:
```bash
kubectl get svc airflow-webserver
```

**วิธีที่ C: Ingress (Production พร้อม HTTPS)**

ดูตัวอย่างใน `examples/values-production.yaml`

---

## Workload Identity

Workload Identity เป็นวิธีที่ปลอดภัยที่สุดในการให้ Airflow เข้าถึง Google Cloud services

### ทำไมต้องใช้ Workload Identity?

| ฟีเจอร์ | Service Account Key | Workload Identity |
|---------|-------------------|-------------------|
| ความปลอดภัย | ⚠️ ต้องจัดเก็บ JSON key | ✅ ไม่มี keys |
| การหมุนเวียน | ⚠️ ต้องทำด้วยตนเอง | ✅ อัตโนมัติ |
| Audit Trail | ⚠️ จำกัด | ✅ ครบถ้วน |
| Complexity | ⚠️ ต้องจัดการ secrets | ✅ Native K8s |

### การตั้งค่าอย่างรวดเร็ว

```bash
# 1. รัน script
./scripts/create-gcp-resources.sh

# 2. อัพเดท values.yaml
sed -i "s/YOUR-PROJECT-ID/your-project-id/g" airflow-helm/values.yaml

# 3. Deploy หรือ upgrade
helm upgrade --install airflow ./airflow-helm -f airflow-helm/values.yaml
```

### ตัวอย่างการใช้งาน

#### GCS Remote Logging
```yaml
airflow:
  config:
    AIRFLOW__LOGGING__REMOTE_LOGGING: "True"
    AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER: "gs://your-bucket/airflow/logs"
```

#### BigQuery Access
```python
from airflow.providers.google.cloud.operators.bigquery import BigQueryInsertJobOperator

task = BigQueryInsertJobOperator(
    task_id="query_bigquery",
    configuration={
        "query": {
            "query": "SELECT * FROM dataset.table LIMIT 10",
            "useLegacySql": False,
        }
    }
)
```

**เอกสารเพิ่มเติม**: [คู่มือ Workload Identity ฉบับสมบูรณ์ (ภาษาไทย)](./examples/WORKLOAD_IDENTITY_SETUP_TH.md)

---

## Custom Docker Images

โปรเจกต์นี้มี Dockerfile 4 แบบสำหรับความต้องการที่ต่างกัน:

### 1. Dockerfile (แนะนำ)
- Image หลักพร้อม dependencies เพิ่มเติม
- ใช้ UV package manager
- รวม system packages

### 2. Dockerfile.multi-stage
- Multi-stage build สำหรับ image ขนาดเล็ก
- แยก build และ runtime stages
- เหมาะสำหรับ production

### 3. Dockerfile.uv-fast
- Build ที่เร็วที่สุดพร้อม layer caching
- เหมาะสำหรับ development
- ใช้ UV caching อย่างเต็มที่

### 4. Dockerfile.slim
- Image ขนาดเล็กที่สุด
- Python packages เท่านั้น
- ไม่มี system packages เพิ่มเติม

### การ Build Custom Image

```bash
cd docker

# Build ด้วย Dockerfile มาตรฐาน
docker build -t airflow-custom:3.1.2 .

# หรือใช้ multi-stage
docker build -f Dockerfile.multi-stage -t airflow-custom:3.1.2-slim .

# Test image
docker run --rm airflow-custom:3.1.2 python -c "import pandas; print(pandas.__version__)"

# Push ไปยัง GCR
docker tag airflow-custom:3.1.2 gcr.io/$GCP_PROJECT_ID/airflow-custom:3.1.2
docker push gcr.io/$GCP_PROJECT_ID/airflow-custom:3.1.2
```

### การใช้ Custom Image ใน Helm

อัพเดท `values.yaml`:
```yaml
airflow:
  image:
    repository: gcr.io/your-project-id/airflow-custom
    tag: "3.1.2"
    pullPolicy: IfNotPresent
```

### Dependencies ที่รวมอยู่

ดู `docker/requirements.txt` สำหรับรายการเต็ม:

```txt
# Google Cloud (ล่าสุด 2025)
google-cloud-storage==3.5.0
google-cloud-bigquery==3.38.0
google-cloud-pubsub==2.33.0
google-cloud-dataproc==5.21.0

# Data Processing
pandas==2.3.3
numpy==2.3.4
pyarrow==19.0.1
polars==1.35.1

# HTTP/API Clients
requests==2.32.5
httpx==0.28.1
aiohttp==3.13.2

# และอื่นๆ...
```

---

## การตั้งค่า Production

### การใช้ Production Values

```bash
# 1. Copy ตัวอย่าง production
cp examples/values-production.yaml my-production-values.yaml

# 2. แก้ไขตามความต้องการ
nano my-production-values.yaml

# 3. Deploy
helm upgrade --install airflow ./airflow-helm -f my-production-values.yaml
```

### ฟีเจอร์ Production

#### High Availability (HA)
```yaml
webserver:
  replicas: 3  # มี webserver หลาย pods

scheduler:
  replicas: 2  # มี scheduler หลาย pods

# Pod Disruption Budget
webserver:
  podDisruptionBudget:
    enabled: true
    minAvailable: 2
```

#### Autoscaling
```yaml
webserver:
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
    targetCPUUtilizationPercentage: 80
```

#### GCS Remote Logging
```yaml
airflow:
  config:
    AIRFLOW__LOGGING__REMOTE_LOGGING: "True"
    AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER: "gs://your-bucket/airflow/logs"
    AIRFLOW__LOGGING__REMOTE_LOG_CONN_ID: "google_cloud_default"
```

#### Cloud SQL Integration
ใช้ `examples/values-cloudsql.yaml`:

```yaml
airflow:
  config:
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:password@localhost:5432/airflow

# Cloud SQL Proxy sidecar
extraContainers:
  webserver:
    - name: cloud-sql-proxy
      image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:latest
      args:
        - "--structured-logs"
        - "--port=5432"
        - "PROJECT_ID:REGION:INSTANCE_NAME"
```

#### Ingress with HTTPS
```yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: airflow.yourdomain.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: airflow-tls
      hosts:
        - airflow.yourdomain.com
```

### Security Best Practices

1. **เปลี่ยน Admin Password**
   ```bash
   kubectl exec -it deployment/airflow-webserver -- airflow users create \
       --username admin \
       --firstname Admin \
       --lastname User \
       --role Admin \
       --email admin@example.com \
       --password your-secure-password
   ```

2. **ใช้ Secrets สำหรับ Sensitive Data**
   ```bash
   kubectl create secret generic airflow-secrets \
       --from-literal=sql-alchemy-conn="postgresql://..." \
       --from-literal=fernet-key="$(python -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())')"
   ```

3. **เปิดใช้งาน Network Policies**
   ```yaml
   networkPolicy:
     enabled: true
   ```

4. **ใช้ Workload Identity** (ไม่มี service account keys)

5. **จำกัด Resource Usage**
   ```yaml
   webserver:
     resources:
       requests:
         cpu: "1000m"
         memory: "2Gi"
       limits:
         cpu: "2000m"
         memory: "4Gi"
   ```

---

## การแก้ไขปัญหา

### Pods ไม่ Running

```bash
# ตรวจสอบ pod status
kubectl get pods

# ดู logs
kubectl logs -f deployment/airflow-webserver

# Describe pod เพื่อดู events
kubectl describe pod airflow-webserver-xxx
```

### ปัญหา Workload Identity

```bash
# ตรวจสอบ annotation
kubectl get sa airflow -o yaml | grep iam.gke.io

# ทดสอบจากใน pod
kubectl exec -it deployment/airflow-webserver -- gcloud auth list

# ตรวจสอบ IAM binding
gcloud iam service-accounts get-iam-policy airflow-sa@PROJECT_ID.iam.gserviceaccount.com
```

### Database Connection Issues

```bash
# ทดสอบ connection จากใน pod
kubectl exec -it deployment/airflow-webserver -- \
    airflow db check

# ตรวจสอบ connection string
kubectl exec -it deployment/airflow-webserver -- \
    printenv | grep SQL_ALCHEMY_CONN
```

### Helm Issues

```bash
# ตรวจสอบ Helm release
helm list

# ดู values ที่ใช้
helm get values airflow

# Debug template
helm template airflow ./airflow-helm -f values.yaml --debug

# Rollback ถ้าจำเป็น
helm rollback airflow
```

### Performance Issues

```bash
# ตรวจสอบ resource usage
kubectl top nodes
kubectl top pods

# ดู pod metrics
kubectl describe pod airflow-webserver-xxx | grep -A 10 "Resources"

# ตรวจสอบ HPA
kubectl get hpa
```

---

## คำถามที่พบบ่อย (FAQ)

### ถาม: ทำไมต้องใช้ UV แทน pip?

**ตอบ**: UV เร็วกว่า pip 10-100 เท่า (เขียนด้วย Rust) และจัดการ dependencies ได้ดีกว่า การ build Docker image จะเร็วขึ้นมาก

### ถาม: สามารถใช้ PostgreSQL แทน bundled database ได้หรือไม่?

**ตอบ**: ได้ครับ! ใช้ `examples/values-cloudsql.yaml` หรือ `examples/values-external-db.yaml` สำหรับ external database

### ถาม: จะเพิ่ม Python packages ได้อย่างไร?

**ตอบ**: เพิ่มใน `docker/requirements.txt` แล้ว rebuild Docker image:
```bash
echo "my-package==1.0.0" >> docker/requirements.txt
docker build -t airflow-custom:latest ./docker
```

### ถาม: สามารถใช้ CeleryExecutor ได้หรือไม่?

**ตอบ**: ได้ แต่ต้องเพิ่ม Redis และแก้ไข configuration ใน values.yaml โปรเจกต์นี้ใช้ KubernetesExecutor ตามค่าเริ่มต้น

### ถาม: ค่าใช้จ่ายเท่าไหร่?

**ตอบ**: ขึ้นอยู่กับ:
- Machine types (e2-standard-4 = ~$120/เดือน/node)
- จำนวน nodes (3-10 nodes พร้อม autoscaling)
- Storage (PersistentVolumes)
- Egress traffic

ประมาณ **$300-600/เดือน** สำหรับ production setup

### ถาม: สามารถใช้ Service Account Keys แทน Workload Identity ได้หรือไม่?

**ตอบ**: ได้ แต่ไม่แนะนำ Workload Identity ปลอดภัยกว่าและเป็น best practice ของ Google

---

## การอัพเกรด

### อัพเกรด Airflow Version

```bash
# 1. อัพเดท image tag ใน values.yaml
nano airflow-helm/values.yaml
# เปลี่ยน tag: "3.1.2" เป็นเวอร์ชันใหม่

# 2. Upgrade ด้วย Helm
helm upgrade airflow ./airflow-helm -f airflow-helm/values.yaml

# 3. ตรวจสอบสถานะ
kubectl rollout status deployment/airflow-webserver
kubectl rollout status deployment/airflow-scheduler
```

### อัพเดท Dependencies

```bash
# 1. แก้ไข requirements.txt
nano docker/requirements.txt

# 2. Rebuild image
docker build -t airflow-custom:new-version ./docker

# 3. Push image
docker push gcr.io/$GCP_PROJECT_ID/airflow-custom:new-version

# 4. อัพเดท values.yaml และ upgrade
helm upgrade airflow ./airflow-helm -f airflow-helm/values.yaml
```

---

## การลบทรัพยากร

### ลบ Airflow Installation

```bash
# Uninstall Helm release
helm uninstall airflow

# ลบ PersistentVolumeClaims (ถ้าต้องการ)
kubectl delete pvc --all

# ลบ namespace (ถ้าสร้างแยก)
kubectl delete namespace airflow
```

### ลบ GKE Cluster

```bash
# ลบ cluster
gcloud container clusters delete $CLUSTER_NAME \
    --zone=$ZONE \
    --project=$GCP_PROJECT_ID

# ลบ service accounts
gcloud iam service-accounts delete airflow-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com \
    --project=$GCP_PROJECT_ID
```

### ลบทรัพยากรทั้งหมดด้วย Script

```bash
./scripts/cleanup.sh
```

---

## ทรัพยากรเพิ่มเติม

### เอกสารภายในโปรเจกต์
- 📖 [Workload Identity Setup (ภาษาไทย)](./examples/WORKLOAD_IDENTITY_SETUP_TH.md)
- 📖 [Workload Identity Setup (English)](./examples/WORKLOAD_IDENTITY_SETUP.md)
- 📝 [ตัวอย่างการตั้งค่า Production](./examples/values-production.yaml)
- 📝 [ตัวอย่างการตั้งค่า Cloud SQL](./examples/values-cloudsql.yaml)

### เอกสารอ้างอิง
- [Apache Airflow Documentation](https://airflow.apache.org/docs/apache-airflow/stable/)
- [GKE Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
- [Helm Charts Documentation](https://helm.sh/docs/)
- [UV Package Manager](https://github.com/astral-sh/uv)

### Community
- [Apache Airflow Slack](https://apache-airflow-slack.herokuapp.com/)
- [Google Cloud Community](https://www.googlecloudcommunity.com/)
- [Kubernetes Thailand Community](https://www.facebook.com/groups/kubernetesthailand/)

---

## การสนับสนุน

หากพบปัญหาหรือมีคำถาม:

1. 📖 ตรวจสอบ [การแก้ไขปัญหา](#การแก้ไขปัญหา)
2. 📖 อ่านเอกสาร [Workload Identity](./examples/WORKLOAD_IDENTITY_SETUP_TH.md)
3. 🐛 เปิด [Issue](https://github.com/piyanats/airflow3-on-gke/issues) ใน GitHub
4. 💬 ถาม Community ใน Airflow Slack

---

## License

โปรเจกต์นี้เป็น open source ภายใต้ MIT License

---

## Credits

สร้างและดูแลโดย: [piyanats](https://github.com/piyanats)

ใช้:
- [Apache Airflow](https://airflow.apache.org/) - Workflow orchestration platform
- [UV](https://github.com/astral-sh/uv) - Fast Python package installer
- [Helm](https://helm.sh/) - Kubernetes package manager
- [Google Kubernetes Engine](https://cloud.google.com/kubernetes-engine) - Managed Kubernetes service

---

## การมีส่วนร่วม

ยินดีรับ contributions! กรุณา:

1. Fork repository
2. สร้าง feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. เปิด Pull Request

---

**หมายเหตุ**: โปรเจกต์นี้ใช้ Apache Airflow 3.1.2 (ล่าสุด ณ พฤศจิกายน 2025) พร้อม dependencies ทั้งหมดที่ updated เป็นเวอร์ชันล่าสุด

🚀 **Happy Airflow-ing on GKE!**
