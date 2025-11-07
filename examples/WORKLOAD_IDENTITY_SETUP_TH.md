# คู่มือการตั้งค่า Workload Identity

คู่มือนี้อธิบายวิธีการตั้งค่า GKE Workload Identity สำหรับ Apache Airflow บน GKE

## Workload Identity คืออะไร?

Workload Identity เป็นวิธีที่ Google แนะนำสำหรับแอปพลิเคชันที่รันบน GKE ให้เข้าถึง Google Cloud services ได้อย่างปลอดภัย โดยมีประโยชน์ดังนี้:

- **การยืนยันตัวตนแบบไม่ใช้ Key**: ไม่ต้องใช้ service account key files
- **หมุนเวียน Credentials อัตโนมัติ**: ระบบจะหมุนเวียน credentials ให้เองโดยอัตโนมัติ
- **การควบคุมสิทธิ์แบบละเอียด**: สามารถกำหนดสิทธิ์แยกแต่ละ service account ได้
- **Audit Logging**: สามารถติดตามได้ว่าใครเข้าถึงทรัพยากรอะไรบ้าง
- **ความปลอดภัยระดับ Pod**: แต่ละ pod จะมี identity ของตัวเอง

## ข้อกำหนดเบื้องต้น

1. GKE cluster ที่เปิดใช้งาน Workload Identity แล้ว
2. Google Cloud project ที่เปิดใช้งาน APIs ที่จำเป็น
3. `gcloud` CLI ที่ตั้งค่าเรียบร้อยแล้ว

## การติดตั้งแบบอัตโนมัติ (แนะนำ)

วิธีที่ง่ายที่สุดในการตั้งค่า Workload Identity คือการใช้ script ที่เตรียมไว้ให้:

```bash
# กำหนด project ID
export GCP_PROJECT_ID="your-project-id"
export NAMESPACE="default"

# รัน setup script
./scripts/create-gcp-resources.sh
```

Script นี้จะทำงานดังนี้:
1. สร้าง GCP service account (`airflow-sa`)
2. มอบสิทธิ์ IAM ที่จำเป็น
3. สร้าง Workload Identity binding
4. แสดง annotation ที่ต้องเพิ่มใน `values.yaml`

## การติดตั้งแบบ Manual

### ขั้นตอนที่ 1: สร้าง GCP Service Account

```bash
# สร้าง service account
gcloud iam service-accounts create airflow-sa \
    --display-name="Airflow Service Account" \
    --project=YOUR-PROJECT-ID
```

### ขั้นตอนที่ 2: มอบสิทธิ์ IAM

มอบสิทธิ์ตามความต้องการของคุณ:

#### สำหรับการเข้าถึง GCS (Remote Logging, DAGs Storage)
```bash
gcloud projects add-iam-policy-binding YOUR-PROJECT-ID \
    --member="serviceAccount:airflow-sa@YOUR-PROJECT-ID.iam.gserviceaccount.com" \
    --role="roles/storage.admin"
```

#### สำหรับการเข้าถึง BigQuery
```bash
gcloud projects add-iam-policy-binding YOUR-PROJECT-ID \
    --member="serviceAccount:airflow-sa@YOUR-PROJECT-ID.iam.gserviceaccount.com" \
    --role="roles/bigquery.dataEditor"

gcloud projects add-iam-policy-binding YOUR-PROJECT-ID \
    --member="serviceAccount:airflow-sa@YOUR-PROJECT-ID.iam.gserviceaccount.com" \
    --role="roles/bigquery.jobUser"
```

#### สำหรับการเข้าถึง Cloud SQL (แนะนำให้ใช้ service account แยก)
```bash
# สร้าง service account แยกสำหรับ Cloud SQL
gcloud iam service-accounts create airflow-db-sa \
    --display-name="Airflow Cloud SQL Service Account" \
    --project=YOUR-PROJECT-ID

# มอบสิทธิ์ Cloud SQL Client
gcloud projects add-iam-policy-binding YOUR-PROJECT-ID \
    --member="serviceAccount:airflow-db-sa@YOUR-PROJECT-ID.iam.gserviceaccount.com" \
    --role="roles/cloudsql.client"
```

### ขั้นตอนที่ 3: สร้าง Workload Identity Binding

ผูก Kubernetes service account เข้ากับ GCP service account:

```bash
# สำหรับการใช้งานทั่วไปของ Airflow
gcloud iam service-accounts add-iam-policy-binding \
    airflow-sa@YOUR-PROJECT-ID.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:YOUR-PROJECT-ID.svc.id.goog[default/airflow]" \
    --project=YOUR-PROJECT-ID

# สำหรับการเข้าถึง Cloud SQL (ถ้าใช้ service account แยก)
gcloud iam service-accounts add-iam-policy-binding \
    airflow-db-sa@YOUR-PROJECT-ID.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:YOUR-PROJECT-ID.svc.id.goog[default/airflow]" \
    --project=YOUR-PROJECT-ID
```

### ขั้นตอนที่ 4: อัพเดท Helm Values

อัพเดทไฟล์ `values.yaml` หรือใช้ตัวอย่าง configuration:

```yaml
serviceAccount:
  create: true
  name: "airflow"
  annotations:
    iam.gke.io/gcp-service-account: airflow-sa@YOUR-PROJECT-ID.iam.gserviceaccount.com
```

### ขั้นตอนที่ 5: Deploy หรือ Upgrade Airflow

```bash
# ติดตั้งใหม่
helm install airflow ./airflow-helm -f values.yaml

# หรืออัพเกรดที่มีอยู่
helm upgrade airflow ./airflow-helm -f values.yaml
```

## ตัวอย่างการตั้งค่า

### ตัวอย่างที่ 1: Airflow พื้นฐานพร้อม GCS Remote Logging

ใช้: `examples/values-production.yaml`

```yaml
serviceAccount:
  annotations:
    iam.gke.io/gcp-service-account: airflow-sa@YOUR-PROJECT-ID.iam.gserviceaccount.com

airflow:
  config:
    AIRFLOW__LOGGING__REMOTE_LOGGING: "True"
    AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER: "gs://your-bucket/airflow/logs"
```

สิทธิ์ที่ต้องการ:
- `roles/storage.admin` (หรือสิทธิ์ storage ที่เฉพาะเจาะจงกว่า)

### ตัวอย่างที่ 2: Cloud SQL พร้อม Workload Identity

ใช้: `examples/values-cloudsql.yaml`

```yaml
serviceAccount:
  annotations:
    iam.gke.io/gcp-service-account: airflow-db-sa@YOUR-PROJECT-ID.iam.gserviceaccount.com
```

สิทธิ์ที่ต้องการ:
- `roles/cloudsql.client`

### ตัวอย่างที่ 3: การเข้าถึงหลาย Services

สำหรับ Airflow ที่ต้องเข้าถึง GCS, BigQuery และ services อื่นๆ:

```yaml
serviceAccount:
  annotations:
    iam.gke.io/gcp-service-account: airflow-sa@YOUR-PROJECT-ID.iam.gserviceaccount.com
```

สิทธิ์ที่ต้องการ:
- `roles/storage.admin`
- `roles/bigquery.dataEditor`
- `roles/bigquery.jobUser`
- `roles/dataproc.editor` (ถ้าใช้ Dataproc)
- `roles/pubsub.editor` (ถ้าใช้ Pub/Sub)

## การตรวจสอบ

### ตรวจสอบ Workload Identity Binding

```bash
# ตรวจสอบ IAM policy binding
gcloud iam service-accounts get-iam-policy \
    airflow-sa@YOUR-PROJECT-ID.iam.gserviceaccount.com
```

ผลลัพธ์ที่คาดหวังควรมี:
```yaml
bindings:
- members:
  - serviceAccount:YOUR-PROJECT-ID.svc.id.goog[default/airflow]
  role: roles/iam.workloadIdentityUser
```

### ทดสอบจาก Pod

Deploy Airflow และทดสอบจากใน pod:

```bash
# ดู pod name
kubectl get pods -n default | grep webserver

# เข้าไปใน pod
kubectl exec -it airflow-webserver-xxx -n default -- bash

# ทดสอบการยืนยันตัวตน GCP
gcloud auth list

# ทดสอบการเข้าถึง GCS
gsutil ls gs://your-bucket/

# ทดสอบการเข้าถึง BigQuery
bq ls
```

## การแก้ไขปัญหา

### ปัญหา: ขึ้น "Permission denied"

**สาเหตุ**: GCP service account ไม่มีสิทธิ์ที่จำเป็น

**วิธีแก้**: มอบสิทธิ์ IAM roles ที่ต้องการให้กับ GCP service account

```bash
gcloud projects add-iam-policy-binding YOUR-PROJECT-ID \
    --member="serviceAccount:airflow-sa@YOUR-PROJECT-ID.iam.gserviceaccount.com" \
    --role="roles/REQUIRED_ROLE"
```

### ปัญหา: "Application Default Credentials not found"

**สาเหตุ**: Workload Identity annotation ไม่ได้ตั้งค่าหรือ binding ไม่ได้สร้าง

**วิธีแก้**:
1. ตรวจสอบ annotation ใน values.yaml
2. ตรวจสอบว่า Workload Identity binding มีอยู่
3. Restart pods หลังจากเพิ่ม annotation

```bash
# ลบ pods เพื่อให้อ่าน annotation ใหม่
kubectl delete pods -l app=airflow
```

### ปัญหา: "Invalid JWT token"

**สาเหตุ**: Workload Identity ไม่ได้เปิดใช้งานที่ cluster หรือ node pool

**วิธีแก้**: ตรวจสอบว่า GKE cluster ของคุณเปิดใช้งาน Workload Identity แล้ว

```bash
# ตรวจสอบสถานะ Workload Identity ของ cluster
gcloud container clusters describe CLUSTER_NAME \
    --zone=ZONE \
    --project=PROJECT_ID \
    --format="value(workloadIdentityConfig.workloadPool)"
```

ผลลัพธ์ที่คาดหวัง: `YOUR-PROJECT-ID.svc.id.goog`

### ปัญหา: ใช้ service account ผิด

**สาเหตุ**: Pods ไม่ได้ใช้ Kubernetes service account ที่ถูกต้อง

**วิธีแก้**: ตรวจสอบว่า pods ใช้ service account ที่ถูกต้อง

```bash
# ตรวจสอบ service account ของ pod
kubectl get pods airflow-webserver-xxx -n default -o yaml | grep serviceAccountName
```

ผลลัพธ์ที่คาดหวัง: `serviceAccountName: airflow`

## แนวทางปฏิบัติด้านความปลอดภัย

1. **หนักแน่วเบา (Principle of Least Privilege)**: มอบเฉพาะสิทธิ์ขั้นต่ำที่จำเป็นเท่านั้น
2. **แยก Service Accounts**: ใช้ service accounts ต่างกันสำหรับวัตถุประสงค์ต่างกัน
   - `airflow-sa` สำหรับการทำงานทั่วไปของ Airflow
   - `airflow-db-sa` สำหรับการเข้าถึง Cloud SQL
3. **Audit Logging**: เปิดใช้งาน Cloud Audit Logs เพื่อติดตามการเข้าถึง
4. **ตรวจสอบเป็นประจำ**: ตรวจสอบและลบสิทธิ์ที่ไม่ใช้แล้วเป็นประจำ
5. **ไม่ใช้ Service Account Keys**: อย่าสร้างหรือใช้ JSON service account keys

## ข้อมูลเพิ่มเติม

- [เอกสาร GKE Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
- [ข้อมูลอ้างอิง IAM Roles](https://cloud.google.com/iam/docs/understanding-roles)
- [Cloud SQL Proxy พร้อม Workload Identity](https://cloud.google.com/sql/docs/postgres/connect-kubernetes-engine)
- [การผสานรวม Airflow กับ GCP](https://airflow.apache.org/docs/apache-airflow-providers-google/stable/index.html)

## คำถามที่พบบ่อย

### ถาม: Workload Identity ต่างจาก Service Account Key อย่างไร?

**ตอบ**:
- **Service Account Key**: ไฟล์ JSON ที่มีอายุยาว ต้องจัดเก็บอย่างปลอดภัย และต้องหมุนเวียนด้วยตนเอง
- **Workload Identity**: ใช้ระบบ token ระยะสั้นที่หมุนเวียนอัตโนมัติ ไม่ต้องจัดเก็บ credentials

### ถาม: สามารถใช้ Workload Identity กับ Cloud SQL ได้หรือไม่?

**ตอบ**: ได้ครับ! ใช้ Cloud SQL Proxy พร้อม Workload Identity เพื่อเชื่อมต่อกับ Cloud SQL อย่างปลอดภัยโดยไม่ต้องใช้ service account key

### ถาม: ต้องเปิดใช้งาน Workload Identity ที่ node pool ด้วยหรือไม่?

**ตอบ**: ไม่จำเป็น เพียงแค่เปิดใช้งานที่ระดับ cluster ด้วย `--workload-pool` flag

### ถาม: สามารถใช้ Service Account เดียวกันสำหรับหลาย namespaces ได้หรือไม่?

**ตอบ**: ได้ แต่ต้องสร้าง Workload Identity binding สำหรับแต่ละ namespace แยกกัน:
```bash
--member "serviceAccount:PROJECT_ID.svc.id.goog[namespace1/airflow]"
--member "serviceAccount:PROJECT_ID.svc.id.goog[namespace2/airflow]"
```

### ถาม: มี Performance impact จากการใช้ Workload Identity หรือไม่?

**ตอบ**: มีน้อยมากหรือไม่มีเลย Workload Identity ใช้ token caching และการหมุนเวียนอัตโนมัติที่มีประสิทธิภาพ

## สรุป

Workload Identity เป็นวิธีที่ดีที่สุดในการให้ Airflow บน GKE เข้าถึง Google Cloud services:

✅ **ความปลอดภัย**: ไม่มี service account keys, credentials หมุนเวียนอัตโนมัติ
✅ **ง่ายต่อการจัดการ**: ไม่ต้องหมุนเวียน keys ด้วยตนเอง
✅ **Audit Trail**: ติดตามการเข้าถึงทรัพยากรได้ครบถ้วน
✅ **Best Practice**: ตามแนวทางที่ Google แนะนำ

### ขั้นตอนสรุป

1. **เปิดใช้งาน Workload Identity** ที่ GKE cluster (ทำแล้วใน `install.sh`)
2. **สร้าง GCP Service Account** และมอบสิทธิ์ที่จำเป็น
3. **สร้าง Workload Identity Binding** ระหว่าง K8s SA และ GCP SA
4. **เพิ่ม Annotation** ใน Helm values.yaml
5. **Deploy Airflow** และทดสอบการเข้าถึง

### การใช้งานเพิ่มเติม

ดูตัวอย่างการตั้งค่าเพิ่มเติมใน:
- `examples/values-production.yaml` - Production setup พร้อม GCS logging
- `examples/values-cloudsql.yaml` - Cloud SQL integration
- `examples/values-custom.yaml` - Custom configuration
- `README.md` - คำแนะนำทั่วไป

## การสนับสนุน

หากพบปัญหาหรือมีคำถาม:
1. ตรวจสอบส่วนการแก้ไขปัญหาด้านบน
2. อ่านเอกสาร GKE Workload Identity
3. ตรวจสอบ logs ของ Airflow: `kubectl logs -f airflow-webserver-xxx`
4. เปิด issue ใน repository ของโปรเจกต์

---

**หมายเหตุ**: เอกสารนี้เป็นส่วนหนึ่งของโปรเจกต์ Apache Airflow 3 on GKE สำหรับการใช้งานใน production แนะนำให้ทดสอบใน development environment ก่อน
