# Quick Setup Guide: External PostgreSQL Database

## วิธีใช้ External PostgreSQL แบบด่วน

### Option 1: ใช้ Google Cloud SQL (แนะนำสำหรับ GCP) 🚀

#### ขั้นตอนที่ 1: สร้าง Cloud SQL Instance

```bash
# Run script อัตโนมัติ
./scripts/create-cloud-sql.sh
```

Script จะสร้าง:
- Cloud SQL PostgreSQL 15 instance
- Database ชื่อ `airflow`
- User `airflow` พร้อม password
- Kubernetes secret สำหรับเก็บ credentials

#### ขั้นตอนที่ 2: ติดตั้ง Airflow ด้วย Cloud SQL

```bash
# แก้ไขไฟล์ examples/values-cloudsql.yaml
# เปลี่ยน PROJECT_ID, REGION, INSTANCE_NAME, PASSWORD

# ติดตั้ง Airflow
helm upgrade --install airflow ./airflow-helm \
    --namespace=default \
    -f examples/values-cloudsql.yaml \
    --wait
```

### Option 2: ใช้ Cloud SQL แบบ Private IP (ไม่ต้องใช้ Proxy)

#### ขั้นตอนที่ 1: สร้าง Cloud SQL ด้วย Private IP

```bash
export USE_PRIVATE_IP=true
./scripts/create-cloud-sql.sh
```

#### ขั้นตอนที่ 2: ใช้ค่า Private IP

```bash
# แก้ไขไฟล์ examples/values-cloudsql-private-ip.yaml
# เปลี่ยน PRIVATE_IP และ PASSWORD

# ติดตั้ง
helm upgrade --install airflow ./airflow-helm \
    -f examples/values-cloudsql-private-ip.yaml
```

### Option 3: ใช้ External PostgreSQL ทั่วไป

```bash
# 1. สร้าง secret สำหรับ database credentials
kubectl create secret generic airflow-db-credentials \
    --from-literal=connection="postgresql+psycopg2://user:pass@host:5432/airflow"

# 2. แก้ไขไฟล์ examples/values-external-db.yaml
# เปลี่ยน connection string

# 3. ติดตั้ง
helm upgrade --install airflow ./airflow-helm \
    -f examples/values-external-db.yaml
```

## การ Config แบบรวดเร็ว

### แบบที่ 1: Cloud SQL ผ่าน Unix Socket (แนะนำ)

```yaml
airflow:
  config:
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:PASSWORD@/airflow?host=/cloudsql/PROJECT:REGION:INSTANCE

postgresql:
  enabled: false

extraContainers:
  webserver:
    - name: cloud-sql-proxy
      image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:latest
      args: ["--structured-logs", "--port=5432", "PROJECT:REGION:INSTANCE"]
  scheduler:
    - name: cloud-sql-proxy
      image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:latest
      args: ["--structured-logs", "--port=5432", "PROJECT:REGION:INSTANCE"]
```

### แบบที่ 2: Private IP (ง่ายที่สุด)

```yaml
airflow:
  config:
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:PASSWORD@10.x.x.x:5432/airflow

postgresql:
  enabled: false
```

### แบบที่ 3: External PostgreSQL Server

```yaml
airflow:
  config:
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:PASSWORD@your-db.example.com:5432/airflow

postgresql:
  enabled: false
```

## Connection String Format

```
# TCP Connection
postgresql+psycopg2://USERNAME:PASSWORD@HOST:PORT/DATABASE

# Unix Socket (Cloud SQL)
postgresql+psycopg2://USERNAME:PASSWORD@/DATABASE?host=/cloudsql/PROJECT:REGION:INSTANCE

# With SSL
postgresql+psycopg2://USERNAME:PASSWORD@HOST:PORT/DATABASE?sslmode=require
```

## การทดสอบ Connection

```bash
# ทดสอบจาก Airflow pod
kubectl exec -n default deployment/airflow-webserver -- airflow db check

# ทดสอบด้วย psql
kubectl exec -it -n default deployment/airflow-webserver -- \
    psql "postgresql://airflow:PASSWORD@HOST:5432/airflow" -c "SELECT 1;"
```

## Troubleshooting

### ปัญหา: Connection refused

```bash
# ตรวจสอบว่า database พร้อมหรือยัง
kubectl logs -n default deployment/airflow-webserver --all-containers

# ตรวจสอบ Cloud SQL Proxy logs
kubectl logs -n default deployment/airflow-webserver -c cloud-sql-proxy
```

### ปัญหา: Authentication failed

```bash
# ตรวจสอบ credentials
kubectl get secret airflow-db-credentials -o yaml

# ทดสอบจาก Cloud Shell
gcloud sql connect INSTANCE_NAME --user=airflow
```

### ปัญหา: SSL required

เพิ่ม `?sslmode=require` ใน connection string:
```
postgresql+psycopg2://user:pass@host:5432/db?sslmode=require
```

## Best Practices

✅ **DO:**
- ใช้ Cloud SQL สำหรับ production
- Enable automatic backups
- ใช้ Workload Identity แทน password
- ใช้ Private IP เมื่อเป็นไปได้
- เก็บ credentials ใน Kubernetes secrets

❌ **DON'T:**
- Hardcode passwords ในไฟล์ values
- ใช้ public IP โดยไม่จำเป็น
- ปิด SSL/TLS ใน production
- ใช้ default password

## ขั้นตอนสำหรับ Production

1. **สร้าง Cloud SQL** ด้วย High Availability:
```bash
gcloud sql instances create airflow-db \
    --tier=db-custom-4-15360 \
    --availability-type=REGIONAL \
    --backup-start-time=03:00
```

2. **Set up Workload Identity**:
```bash
./scripts/create-gcp-resources.sh
```

3. **Enable Cloud SQL IAM authentication**:
```bash
gcloud sql users create airflow-sa@PROJECT_ID.iam \
    --instance=airflow-db \
    --type=CLOUD_IAM_SERVICE_ACCOUNT
```

4. **Deploy Airflow**:
```bash
helm upgrade --install airflow ./airflow-helm \
    -f examples/values-production.yaml
```

## เอกสารเพิ่มเติม

- [Full External DB Guide](EXTERNAL_POSTGRESQL.md)
- [Cloud SQL Best Practices](https://cloud.google.com/sql/docs/postgres/best-practices)
- [Airflow Database Configuration](https://airflow.apache.org/docs/apache-airflow/stable/howto/set-up-database.html)
