# การใช้ External PostgreSQL กับ Airflow บน GKE

คู่มือนี้อธิบายวิธีการกำหนดค่า Airflow ให้ใช้ external PostgreSQL database แทน PostgreSQL pod ที่มาพร้อม

## ทำไมต้องใช้ External PostgreSQL?

External PostgreSQL (เช่น Cloud SQL) ให้:
- ✅ Managed service พร้อมการสำรองข้อมูลอัตโนมัติ
- ✅ High availability และ disaster recovery
- ✅ ประสิทธิภาพและ scalability ที่ดีกว่า
- ✅ การอัปเดตและบำรุงรักษาอัตโนมัติ
- ✅ Point-in-time recovery
- ✅ ไม่ต้องจัดการ database pods

## ตัวเลือกที่ 1: ใช้ Google Cloud SQL (แนะนำสำหรับ GCP)

### ขั้นตอนที่ 1: สร้าง Cloud SQL Instance

รัน script ที่ให้มา:

```bash
./scripts/create-cloud-sql.sh
```

หรือแบบ manual:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export INSTANCE_NAME="airflow-db"

# สร้าง Cloud SQL instance
gcloud sql instances create $INSTANCE_NAME \
    --database-version=POSTGRES_15 \
    --tier=db-custom-2-7680 \
    --region=$REGION \
    --network=default \
    --no-assign-ip \
    --database-flags=max_connections=200

# สร้าง database
gcloud sql databases create airflow \
    --instance=$INSTANCE_NAME

# สร้าง user
gcloud sql users create airflow \
    --instance=$INSTANCE_NAME \
    --password=CHANGE_THIS_PASSWORD
```

### ขั้นตอนที่ 2: กำหนดค่า Airflow ให้ใช้ Cloud SQL

สร้างไฟล์ values แบบ custom `values-cloudsql.yaml`:

```yaml
airflow:
  config:
    # ปิดการใช้งาน bundled PostgreSQL
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:PASSWORD@/airflow?host=/cloudsql/PROJECT:REGION:INSTANCE_NAME

postgresql:
  # ปิดการใช้งาน bundled PostgreSQL
  enabled: false

# เปิดใช้งาน Cloud SQL Proxy sidecar
cloudSqlProxy:
  enabled: true
  instances:
    - project: YOUR_PROJECT_ID
      region: us-central1
      instance: airflow-db
```

### ขั้นตอนที่ 3: ติดตั้งด้วย Cloud SQL

```bash
helm upgrade --install airflow ./airflow-helm \
    --namespace=default \
    -f values-cloudsql.yaml \
    --wait
```

## ตัวเลือกที่ 2: ใช้ Cloud SQL กับ Private IP

### ขั้นตอนที่ 1: สร้าง Cloud SQL ด้วย Private IP

```bash
# สร้าง instance ด้วย private IP
gcloud sql instances create $INSTANCE_NAME \
    --database-version=POSTGRES_15 \
    --tier=db-custom-2-7680 \
    --region=$REGION \
    --network=default \
    --no-assign-ip

# รับ private IP
PRIVATE_IP=$(gcloud sql instances describe $INSTANCE_NAME \
    --format='get(ipAddresses[0].ipAddress)')

echo "Private IP: $PRIVATE_IP"
```

### ขั้นตอนที่ 2: กำหนดค่า Airflow

```yaml
airflow:
  config:
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:PASSWORD@PRIVATE_IP:5432/airflow

postgresql:
  enabled: false
```

## ตัวเลือกที่ 3: ใช้ External PostgreSQL (ทุก Provider)

สำหรับ external PostgreSQL database ใดๆ:

### ขั้นตอนที่ 1: เตรียม Database

1. สร้าง database: `airflow`
2. สร้าง user: `airflow` พร้อม password
3. ให้สิทธิ์:
   ```sql
   GRANT ALL PRIVILEGES ON DATABASE airflow TO airflow;
   ```

### ขั้นตอนที่ 2: สร้าง Kubernetes Secret

```bash
kubectl create secret generic airflow-db-secret \
    --from-literal=connection="postgresql+psycopg2://USER:PASSWORD@HOST:5432/DATABASE" \
    -n default
```

### ขั้นตอนที่ 3: กำหนดค่า values.yaml

```yaml
airflow:
  config:
    # ใช้ secret reference
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:PASSWORD@your-db-host:5432/airflow

postgresql:
  # ปิดการใช้งาน bundled PostgreSQL
  enabled: false
```

## ตัวเลือกที่ 4: ใช้ Cloud SQL กับ Workload Identity (ปลอดภัยที่สุด)

### ขั้นตอนที่ 1: ตั้งค่า Workload Identity

```bash
# สร้าง service account
gcloud iam service-accounts create airflow-db-sa \
    --display-name="Airflow DB Service Account"

# ให้สิทธิ์ Cloud SQL Client role
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:airflow-db-sa@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/cloudsql.client"

# ผูก Kubernetes SA กับ GCP SA
gcloud iam service-accounts add-iam-policy-binding \
    airflow-db-sa@$PROJECT_ID.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:$PROJECT_ID.svc.id.goog[default/airflow]"
```

### ขั้นตอนที่ 2: กำหนดค่า Helm Values

```yaml
serviceAccount:
  create: true
  name: airflow
  annotations:
    iam.gke.io/gcp-service-account: airflow-db-sa@PROJECT_ID.iam.gserviceaccount.com

airflow:
  config:
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:PASSWORD@/airflow?host=/cloudsql/PROJECT:REGION:INSTANCE

postgresql:
  enabled: false

# Cloud SQL Proxy sidecar
extraContainers:
  - name: cloud-sql-proxy
    image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:latest
    args:
      - "--structured-logs"
      - "--port=5432"
      - "PROJECT:REGION:INSTANCE"
    securityContext:
      runAsNonRoot: true
```

## ตัวอย่างการกำหนดค่า

### การกำหนดค่า External DB แบบ Minimal

```yaml
# values-external-db.yaml
airflow:
  config:
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:password@postgres-host:5432/airflow

postgresql:
  enabled: false
```

### การกำหนดค่า Cloud SQL สำหรับ Production

```yaml
# values-cloudsql-production.yaml
airflow:
  config:
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:PASSWORD@/airflow?host=/cloudsql/PROJECT:REGION:INSTANCE
    AIRFLOW__DATABASE__SQL_ALCHEMY_POOL_SIZE: "10"
    AIRFLOW__DATABASE__SQL_ALCHEMY_MAX_OVERFLOW: "20"
    AIRFLOW__DATABASE__SQL_ALCHEMY_POOL_RECYCLE: "3600"
    AIRFLOW__DATABASE__SQL_ALCHEMY_POOL_PRE_PING: "True"

postgresql:
  enabled: false

serviceAccount:
  annotations:
    iam.gke.io/gcp-service-account: airflow-db-sa@PROJECT_ID.iam.gserviceaccount.com
```

## รูปแบบ Connection String

### Standard TCP Connection
```
postgresql+psycopg2://USERNAME:PASSWORD@HOST:PORT/DATABASE
```

### Cloud SQL ด้วย Unix Socket
```
postgresql+psycopg2://USERNAME:PASSWORD@/DATABASE?host=/cloudsql/PROJECT:REGION:INSTANCE
```

### กับ SSL
```
postgresql+psycopg2://USERNAME:PASSWORD@HOST:PORT/DATABASE?sslmode=require
```

### กับ Connection Pooling Parameters
```
postgresql+psycopg2://USER:PASS@HOST:PORT/DB?pool_size=10&max_overflow=20
```

## ข้อกำหนดของ Database

- PostgreSQL 12+
- Extensions ที่จำเป็น:
  - `pg_trgm` (สำหรับการค้นหา)
  - `btree_gin` (สำหรับการ indexing)

## การเริ่มต้น Database

เมื่อใช้ external database, Airflow จะทำโดยอัตโนมัติ:

1. รัน migrations เมื่อเริ่มครั้งแรก (ผ่าน init container)
2. สร้าง tables และ indexes ที่จำเป็น
3. สร้าง admin user (ถ้ากำหนดค่าไว้)

คุณสามารถตรวจสอบด้วย:

```bash
# ตรวจสอบการเชื่อมต่อ database
kubectl exec -n default deployment/airflow-webserver -- airflow db check

# ตรวจสอบเวอร์ชัน database
kubectl exec -n default deployment/airflow-webserver -- airflow db shell
```

## การแก้ไขปัญหา

### Connection Refused

```bash
# ทดสอบการเชื่อมต่อจาก pod
kubectl exec -it deployment/airflow-webserver -n default -- \
    psql "postgresql://airflow:PASSWORD@HOST:5432/airflow" -c "SELECT 1;"
```

### ปัญหา SSL/TLS

เพิ่ม SSL mode ใน connection string:
```
?sslmode=require
```

หรือปิดสำหรับการทดสอบ (ไม่แนะนำสำหรับ production):
```
?sslmode=disable
```

### ปัญหาการเชื่อมต่อ Cloud SQL

ตรวจสอบ Cloud SQL Proxy logs:
```bash
kubectl logs -n default deployment/airflow-webserver -c cloud-sql-proxy
```

ตรวจสอบชื่อ instance connection:
```bash
gcloud sql instances describe INSTANCE_NAME \
    --format='get(connectionName)'
```

### ปัญหาการยืนยันตัวตน

1. ตรวจสอบ credentials ใน secret
2. ตรวจสอบสิทธิ์ user ใน database
3. ตรวจสอบ IP allowlist (สำหรับ public IP connections)

## การปรับแต่งประสิทธิภาพ

สำหรับประสิทธิภาพที่ดีกว่ากับ external database:

```yaml
airflow:
  config:
    # การตั้งค่า Connection pool
    AIRFLOW__DATABASE__SQL_ALCHEMY_POOL_SIZE: "20"
    AIRFLOW__DATABASE__SQL_ALCHEMY_MAX_OVERFLOW: "40"
    AIRFLOW__DATABASE__SQL_ALCHEMY_POOL_RECYCLE: "3600"
    AIRFLOW__DATABASE__SQL_ALCHEMY_POOL_PRE_PING: "True"

    # การปรับแต่ง Query
    AIRFLOW__DATABASE__SQL_ALCHEMY_SCHEMA: "public"
    AIRFLOW__CORE__SQL_ALCHEMY_POOL_ENABLED: "True"
```

## Best Practices ด้านความปลอดภัย

1. **ใช้ secrets** - เก็บ credentials ใน Kubernetes secrets
2. **เปิดใช้งาน SSL/TLS** - ใช้ encrypted connections เสมอ
3. **Private IP** - ใช้ private networking เมื่อเป็นไปได้
4. **Workload Identity** - ใช้ GCP Workload Identity แทน passwords
5. **Least privilege** - ให้เฉพาะสิทธิ์ database ที่จำเป็น
6. **Rotate credentials** - หมุนเวียน database passwords เป็นประจำ
7. **Network policies** - จำกัดการเข้าถึง network ไปยัง database

## Migration จาก Bundled PostgreSQL

เพื่อย้ายข้อมูลจาก bundled PostgreSQL ไปยัง external:

```bash
# 1. สำรองข้อมูล existing database
./scripts/backup.sh

# 2. Export data
kubectl exec -n default deployment/postgres -- \
    pg_dump -U airflow airflow > airflow-backup.sql

# 3. Import ไปยัง external database
psql "postgresql://airflow:PASSWORD@HOST:5432/airflow" < airflow-backup.sql

# 4. อัปเดต Helm values
helm upgrade airflow ./airflow-helm \
    -f values-external-db.yaml

# 5. ตรวจสอบ migration
kubectl exec -n default deployment/airflow-webserver -- airflow db check
```

## Examples Repository

ดูใน `examples/` directory สำหรับ:
- `values-cloudsql.yaml` - การกำหนดค่า Cloud SQL
- `values-external-db.yaml` - การกำหนดค่า external DB ทั่วไป
- `values-cloudsql-workload-identity.yaml` - การตั้งค่า Cloud SQL ที่ปลอดภัย

## ทรัพยากรเพิ่มเติม

- [Cloud SQL Documentation](https://cloud.google.com/sql/docs)
- [Airflow Database Configuration](https://airflow.apache.org/docs/apache-airflow/stable/howto/set-up-database.html)
- [Cloud SQL Proxy](https://cloud.google.com/sql/docs/postgres/connect-kubernetes-engine)
