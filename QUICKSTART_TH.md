# คู่มือเริ่มต้นอย่างรวดเร็ว - Apache Airflow 3 บน GKE

คู่มือนี้จะช่วยให้คุณติดตั้ง Apache Airflow 3 บน GKE ได้ภายในไม่กี่นาที

## ข้อกำหนดเบื้องต้น

- บัญชี Google Cloud พร้อม billing ที่เปิดใช้งาน
- ติดตั้ง `gcloud`, `kubectl`, และ `helm` แล้ว
- สร้าง GCP project แล้ว

## ขั้นตอนที่ 1: ตั้งค่า GCP Project

```bash
# Login เข้า GCP
gcloud auth login

# ตั้งค่า project
export GCP_PROJECT_ID="your-project-id"
gcloud config set project $GCP_PROJECT_ID

# เปิดใช้งาน APIs ที่จำเป็น
gcloud services enable container.googleapis.com
gcloud services enable compute.googleapis.com
```

## ขั้นตอนที่ 2: ติดตั้งอย่างรวดเร็ว

```bash
# Clone repository
git clone <your-repo-url>
cd airflow3-on-gke

# รัน script ติดตั้ง
./install.sh
```

Script จะทำให้โดยอัตโนมัติ:
1. สร้าง GKE cluster (ถ้าจำเป็น)
2. ติดตั้ง Airflow ด้วย Helm
3. ตั้งค่าทรัพยากรที่จำเป็นทั้งหมด

## ขั้นตอนที่ 3: เข้าถึง Airflow UI

### ตัวเลือก A: Port Forward (แนะนำสำหรับการทดสอบ)

```bash
kubectl port-forward -n default svc/airflow-webserver 8080:8080
```

จากนั้นเปิด: http://localhost:8080

### ตัวเลือก B: LoadBalancer (ถ้าเปิดใช้งาน)

```bash
# รับ external IP
kubectl get service airflow-webserver -n default

# รอให้ EXTERNAL-IP ถูก assign
# จากนั้นเข้าถึง: http://<EXTERNAL-IP>:8080
```

### ข้อมูลการเข้าสู่ระบบเริ่มต้น

- Username: `admin`
- Password: `admin`

**สำคัญ**: เปลี่ยน credentials เหล่านี้หลังจาก login ครั้งแรก!

## ขั้นตอนที่ 4: Deploy DAG แรกของคุณ

```bash
# รับชื่อ webserver pod
POD_NAME=$(kubectl get pods -n default -l component=webserver -o jsonpath='{.items[0].metadata.name}')

# คัดลอก example DAG
kubectl cp examples/dags/example_dag.py default/$POD_NAME:/opt/airflow/dags/

# รอสักครู่เพื่อให้ DAG ปรากฏใน UI
```

## ขั้นตอนที่ 5: ตรวจสอบการติดตั้ง

```bash
# รัน test script
./scripts/test-deployment.sh

# ตรวจสอบว่า pods ทั้งหมดทำงานอยู่
kubectl get pods -n default -l app=airflow

# ดู logs
kubectl logs -n default -l component=webserver --tail=50
```

## ขั้นตอนถัดไป?

### กำหนดค่า Git-Sync สำหรับ DAGs

แก้ไข `airflow-helm/values.yaml`:

```yaml
dags:
  gitSync:
    enabled: true
    repo: "https://github.com/your-org/your-dags.git"
    branch: "main"
    subPath: "dags"
```

จากนั้น upgrade:

```bash
./upgrade.sh
```

### เปิดใช้งาน Ingress พร้อม Custom Domain

1. ติดตั้ง nginx ingress controller:
```bash
helm install nginx-ingress ingress-nginx/ingress-nginx
```

2. อัปเดต `airflow-helm/values.yaml`:
```yaml
ingress:
  enabled: true
  hosts:
    - host: airflow.yourdomain.com
```

3. Upgrade การติดตั้ง:
```bash
./upgrade.sh
```

### ตั้งค่าแบบ Production

สำหรับการใช้งาน production ดูที่ [examples/values-production.yaml](examples/values-production.yaml)

การเปลี่ยนแปลงสำคัญสำหรับ production:
- ใช้ Cloud SQL แทน PostgreSQL pod
- เปิดใช้งาน remote logging ไปยัง GCS
- กำหนดค่า Workload Identity
- เปิดใช้งาน HTTPS/TLS
- เพิ่ม replicas สำหรับ HA
- ตั้งค่า monitoring

## คำสั่งที่ใช้บ่อย

```bash
# ดู pods ทั้งหมด
kubectl get pods -n default

# ดู webserver logs
kubectl logs -n default -l component=webserver -f

# ดู scheduler logs
kubectl logs -n default -l component=scheduler -f

# แสดงรายการ DAGs
kubectl exec -n default deployment/airflow-webserver -- airflow dags list

# เข้าสู่ shell
kubectl exec -it -n default deployment/airflow-webserver -- /bin/bash

# Upgrade Airflow
./upgrade.sh

# ถอนการติดตั้ง Airflow
./uninstall.sh
```

## การแก้ไขปัญหา

### Pods ไม่เริ่มต้น

```bash
kubectl describe pod <pod-name> -n default
kubectl logs <pod-name> -n default
```

### ไม่สามารถเข้าถึง UI

```bash
# ตรวจสอบ service
kubectl get service airflow-webserver -n default

# ใช้ port-forward
kubectl port-forward -n default svc/airflow-webserver 8080:8080
```

### Database connection errors

```bash
# ตรวจสอบ database pod
kubectl get pod -n default -l app=postgres

# ทดสอบการเชื่อมต่อ
kubectl exec -n default deployment/airflow-webserver -- airflow db check
```

## ลบทิ้ง

เพื่อลบทุกอย่าง:

```bash
./uninstall.sh
```

จะทำให้:
1. ถอนการติดตั้ง Airflow
2. ลบ PVCs
3. ลบ GKE cluster (ถ้าเลือก)

## ทรัพยากร

- เอกสารฉบับเต็ม: [README_TH.md](README_TH.md)
- การตั้งค่า Production: [examples/values-production.yaml](examples/values-production.yaml)
- บันทึกการพัฒนา: [NOTES_TH.md](NOTES_TH.md)

## การสนับสนุน

สำหรับปัญหาต่างๆ ให้ตรวจสอบ:
1. Pod logs: `kubectl logs <pod-name> -n default`
2. Pod events: `kubectl describe pod <pod-name> -n default`
3. Service status: `kubectl get all -n default`

สำหรับความช่วยเหลือเพิ่มเติม ดูที่ [README_TH.md](README_TH.md) หรือเปิด issue
