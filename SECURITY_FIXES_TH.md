# การแก้ไขและปรับปรุงด้านความปลอดภัยที่ใช้แล้ว

## วันที่: 2025-11-07

เอกสารนี้อธิบายการแก้ไขและปรับปรุงด้านความปลอดภัยที่สำคัญทั้งหมดที่ใช้กับโครงการ Airflow 3 บน GKE

## การแก้ไขความปลอดภัยที่สำคัญ

### 1. แก้ไข Hardcoded Secrets (สำคัญมาก)
**ไฟล์ที่แก้ไข:**
- `airflow-helm/templates/secret.yaml`
- `airflow-helm/values.yaml`

**การเปลี่ยนแปลง:**
- ลบ fernet key และ webserver secret key ที่ hardcoded
- ตอนนี้ต้องตั้งค่าใน values.yaml
- เพิ่มคำแนะนำที่ชัดเจนสำหรับการสร้าง secure keys
- Helm chart จะล้มเหลวพร้อมข้อความอธิบายถ้าไม่ได้ระบุ secrets

**สร้าง Secrets:**
```bash
# สร้าง Fernet Key
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"

# สร้าง Webserver Secret
openssl rand -base64 32
```

### 2. แก้ไข Hardcoded Database Password (สำคัญมาก)
**ไฟล์ที่แก้ไข:**
- `airflow-helm/values.yaml`
- `airflow-helm/templates/postgres-deployment.yaml`
- `airflow-helm/templates/postgres-secret.yaml` (ใหม่)

**การเปลี่ยนแปลง:**
- เปลี่ยนรหัสผ่าน PostgreSQL เริ่มต้นจาก "airflow" เป็นต้องกำหนดค่า
- ย้ายรหัสผ่าน PostgreSQL ไปยัง Kubernetes Secret
- เพิ่มคำเตือนที่ชัดเจนใน values.yaml เกี่ยวกับการเปลี่ยนรหัสผ่าน

### 3. แก้ไข Hardcoded Admin Credentials (สำคัญมาก)
**ไฟล์ที่แก้ไข:**
- `airflow-helm/templates/webserver-deployment.yaml`
- `airflow-helm/values.yaml`

**การเปลี่ยนแปลง:**
- Username และ password ของ Admin สามารถกำหนดค่าผ่าน values.yaml
- เพิ่มส่วนการกำหนดค่า admin user พร้อมคำเตือนที่ชัดเจน
- Init container ตอนนี้ใช้ credentials แบบ templated

## การแก้ไขบั๊กที่มีความสำคัญสูง

### 4. แก้ไขปัญหา RBAC Scope
**ไฟล์ที่แก้ไข:**
- `airflow-helm/templates/rbac.yaml`

**การเปลี่ยนแปลง:**
- เปลี่ยนจาก `Role` เป็น `ClusterRole`
- เปลี่ยนจาก `RoleBinding` เป็น `ClusterRoleBinding`
- เพิ่ม namespace ใน ClusterRoleBinding subjects
- เพิ่มสิทธิ์เพิ่มเติมสำหรับ pod/status และ configmaps
- แก้ไข KubernetesExecutor cross-namespace worker pod creation

### 5. แก้ไขการติดตั้ง UV ซ้ำใน Dockerfile
**ไฟล์ที่แก้ไข:**
- `docker/Dockerfile`

**การเปลี่ยนแปลง:**
- ลบการติดตั้ง UV ซ้ำ (ติดตั้งสองครั้ง)
- ลดเวลา build และขนาด image

### 6. แก้ไขปัญหา Chart.Name vs Release.Name
**ไฟล์ที่แก้ไข:** (อัปเดต Helm templates ทั้งหมด)
- `airflow-helm/templates/webserver-deployment.yaml`
- `airflow-helm/templates/scheduler-deployment.yaml`
- `airflow-helm/templates/postgres-deployment.yaml`
- `airflow-helm/templates/configmap.yaml`
- `airflow-helm/templates/secret.yaml`
- `airflow-helm/templates/webserver-service.yaml`
- `airflow-helm/templates/rbac.yaml`
- `airflow-helm/templates/pvc-dags.yaml`
- `airflow-helm/templates/pvc-logs.yaml`
- `airflow-helm/templates/serviceaccount.yaml`
- `airflow-helm/templates/ingress.yaml`

**การเปลี่ยนแปลง:**
- เปลี่ยนทรัพยากรทั้งหมดให้ใช้ `{{ .Release.Name }}` แทน `{{ .Chart.Name }}`
- อนุญาตให้มี multiple Airflow releases ใน namespace เดียวกัน
- ป้องกันความขัดแย้งของชื่อทรัพยากร
- เพิ่ม label `release: {{ .Release.Name }}` ในทรัพยากรทั้งหมด

### 7. เพิ่ม Scheduler Readiness Probe
**ไฟล์ที่แก้ไข:**
- `airflow-helm/templates/scheduler-deployment.yaml`

**การเปลี่ยนแปลง:**
- เพิ่ม readinessProbe สำหรับ scheduler container
- ป้องกันการ route traffic ก่อน scheduler พร้อมใช้งาน
- ใช้ health check เดียวกับ liveness probe

## การปรับปรุงที่มีความสำคัญปานกลาง

### 8. เพิ่ม Resource Limits ใน Init Containers
**ไฟล์ที่แก้ไข:**
- `airflow-helm/templates/webserver-deployment.yaml`
- `airflow-helm/templates/scheduler-deployment.yaml`

**การเปลี่ยนแปลง:**
- เพิ่ม CPU และ memory limits ใน init containers ทั้งหมด
- ป้องกัน init containers จากการใช้ทรัพยากรมากเกินไป
- wait-for-db: 100m CPU / 128Mi memory (request), 200m / 256Mi (limit)
- init-db: 200m CPU / 256Mi memory (request), 500m / 512Mi (limit)

### 9. เพิ่ม Database Connection Timeout
**ไฟล์ที่แก้ไข:**
- `airflow-helm/templates/webserver-deployment.yaml`
- `airflow-helm/templates/scheduler-deployment.yaml`

**การเปลี่ยนแปลง:**
- เพิ่ม MAX_RETRIES (60 attempts = 5 นาที) ใน wait-for-db init containers
- ป้องกัน infinite loops ถ้า database กำหนดค่าผิด
- ให้ข้อความ error ที่ชัดเจนเมื่อ timeout

### 10. เพิ่ม PostgreSQL Health Checks
**ไฟล์ที่แก้ไข:**
- `airflow-helm/templates/postgres-deployment.yaml`

**การเปลี่ยนแปลง:**
- เพิ่ม livenessProbe โดยใช้ pg_isready
- เพิ่ม readinessProbe โดยใช้ pg_isready
- ตรวจสอบว่า PostgreSQL สุขภาพดีก่อนรับการเชื่อมต่อ

### 11. เพิ่ม PostgreSQL Security Context
**ไฟล์ที่แก้ไข:**
- `airflow-helm/templates/postgres-deployment.yaml`

**การเปลี่ยนแปลง:**
- เพิ่ม pod security context
- รันในฐานะ non-root user (UID 999)
- ตั้ง fsGroup สำหรับสิทธิ์ volume
- ปฏิบัติตาม Kubernetes security best practices

## ไฟล์ที่สร้างใหม่

### ไฟล์ใหม่:
1. `airflow-helm/templates/postgres-secret.yaml` - Kubernetes Secret สำหรับรหัสผ่าน PostgreSQL
2. `SECURITY_FIXES_TH.md` - เอกสารนี้

## หมายเหตุการ Deployment

### การเปลี่ยนแปลงที่ทำลาย:
⚠️ **สำคัญ**: การเปลี่ยนแปลงเหล่านี้แนะนำการเปลี่ยนแปลงที่ทำลายซึ่งต้องมีการอัปเดตการกำหนดค่าก่อนการ deploy

1. **ค่าที่ต้องการ** - คุณต้องตั้งค่าเหล่านี้ใน values.yaml ก่อน deploy:
   ```yaml
   airflow:
     fernetKey: "<YOUR_GENERATED_FERNET_KEY>"
     webserverSecretKey: "<YOUR_GENERATED_SECRET>"
     adminUser:
       password: "<YOUR_ADMIN_PASSWORD>"  # เปลี่ยนจากค่าเริ่มต้น

   postgresql:
     auth:
       password: "<YOUR_DB_PASSWORD>"  # เปลี่ยนจากค่าเริ่มต้น
   ```

2. **การเปลี่ยนแปลงชื่อทรัพยากร** - ทรัพยากรทั้งหมดตอนนี้ใช้ release name แทน chart name:
   - เก่า: `airflow-webserver`, `airflow-secret`, etc.
   - ใหม่: `<release-name>-webserver`, `<release-name>-secret`, etc.
   - ถ้า upgrade deployment ที่มีอยู่ อาจทำให้สร้างทรัพยากรใหม่

3. **การเปลี่ยนแปลง RBAC** - ClusterRole/ClusterRoleBinding แทน Role/RoleBinding:
   - ให้สิทธิ์มากขึ้น (cluster-wide)
   - อาจต้องมีสิทธิ์ RBAC เพิ่มเติมเพื่อ deploy

### Migration จากเวอร์ชันเก่า:

ถ้าคุณมี deployment ที่มีอยู่ คุณควร:

1. **สำรองข้อมูล deployment ปัจจุบัน**:
   ```bash
   kubectl get all -n <namespace> -o yaml > backup.yaml
   helm get values <release-name> -n <namespace> > old-values.yaml
   ```

2. **สร้าง secrets ใหม่**:
   ```bash
   # Fernet key
   python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"

   # Webserver secret
   openssl rand -base64 32

   # Database password
   openssl rand -base64 16
   ```

3. **อัปเดต values.yaml** ด้วยฟิลด์ที่ต้องการใหม่

4. **พิจารณาการติดตั้งใหม่** แทนการ upgrade เนื่องจากการเปลี่ยนชื่อทรัพยากร:
   ```bash
   # ถอนการติดตั้งเก่า
   helm uninstall <release-name> -n <namespace>

   # ติดตั้งใหม่ด้วย values ที่อัปเดต
   helm install <release-name> ./airflow-helm -f updated-values.yaml -n <namespace>
   ```

## การตรวจสอบ

เพื่อตรวจสอบ Helm chart หลังการเปลี่ยนแปลงเหล่านี้:

```bash
# Lint chart
helm lint ./airflow-helm

# Dry-run เพื่อตรวจสอบ errors
helm install test-release ./airflow-helm \
  --dry-run \
  --debug \
  -f your-values.yaml

# Template เพื่อดู YAML ที่สร้าง
helm template test-release ./airflow-helm -f your-values.yaml
```

## Checklist ความปลอดภัยสำหรับ Production

- [ ] สร้าง Fernet key ที่ไม่ซ้ำ
- [ ] สร้าง webserver secret key ที่ไม่ซ้ำ
- [ ] เปลี่ยนรหัสผ่าน admin จากค่าเริ่มต้น
- [ ] เปลี่ยนรหัสผ่าน PostgreSQL จากค่าเริ่มต้น
- [ ] ตรวจสอบและจำกัดสิทธิ์ RBAC ถ้าจำเป็น
- [ ] กำหนดค่า TLS/HTTPS ผ่าน Ingress
- [ ] เปิดใช้งาน Cloud SQL สำหรับ production database (ปิด bundled PostgreSQL)
- [ ] กำหนดค่า GCS remote logging
- [ ] ตั้งค่า Workload Identity สำหรับการเข้าถึง GCP
- [ ] กำหนดค่า resource limits อย่างเหมาะสม
- [ ] ตรวจสอบ network policies
- [ ] ตั้งค่า monitoring และ alerting

## คำแนะนำเพิ่มเติม

แม้ว่าจะไม่ได้ implement ใน fix set นี้ พิจารณาเหล่านี้สำหรับ production:

1. **External Secrets Operator**: ผสานรวมกับ GCP Secret Manager หรือคล้ายกัน
2. **Pod Security Standards**: ใช้ restrictive pod security policies
3. **Network Policies**: implement network segmentation
4. **Image Scanning**: สแกน container images หาช่องโหว่
5. **Audit Logging**: เปิดใช้งาน Kubernetes audit logs
6. **Backup Strategy**: implement การสำรองข้อมูล database เป็นประจำ
7. **Disaster Recovery**: จัดทำเอกสารและทดสอบขั้นตอน DR

## การทดสอบ

หลังใช้ fixes เหล่านี้ ทดสอบ:

1. การตรวจสอบ Helm chart:
   ```bash
   helm lint ./airflow-helm
   ```

2. Deployment พร้อม secrets ที่เหมาะสม:
   ```bash
   helm install test ./airflow-helm -f test-values.yaml --dry-run
   ```

3. ตรวจสอบการสร้างทรัพยากร:
   ```bash
   kubectl get all -n <namespace>
   ```

4. ตรวจสอบความปลอดภัย:
   ```bash
   kubectl get secrets -n <namespace>
   kubectl describe pod <pod-name> -n <namespace>
   ```

## สรุป

**จำนวน Fixes ที่ใช้ทั้งหมด**: 11
- ความปลอดภัยสำคัญ: 3
- บั๊กที่มีความสำคัญสูง: 4
- ความสำคัญปานกลาง: 4

ช่องโหว่ความปลอดภัยที่สำคัญทั้งหมดได้รับการแก้ไขแล้ว โครงการตอนนี้ปลอดภัยและพร้อมสำหรับ production มากขึ้นอย่างมาก
