# บันทึกการพัฒนา

## การเปลี่ยนแปลงสำคัญใน Airflow 3

Apache Airflow 3.0 มีการเปลี่ยนแปลงสำคัญหลายอย่างจากเวอร์ชัน 2.x:

### Breaking Changes
- ต้องใช้ Python 3.8+ (แนะนำ 3.12)
- ลบฟีเจอร์ที่ deprecated จาก 2.x
- อัปเดต database schema
- เปลี่ยนแปลง operator interfaces
- อัปเดตกลไกการยืนยันตัวตน

### ฟีเจอร์ใหม่
- ปรับปรุง Kubernetes executor
- DAG serialization ที่ดีขึ้น
- ปรับปรุงการ execute task
- UI/UX ที่ดีขึ้น
- Observability ที่ดีขึ้น

## ข้อพิจารณาเฉพาะสำหรับ GKE

### Storage Classes
- `standard`: Standard persistent disk (HDD)
- `standard-rwo`: Standard persistent disk (ReadWriteOnce)
- `premium-rwo`: SSD persistent disk (ReadWriteOnce)

สำหรับ production แนะนำให้ใช้ `premium-rwo` เพื่อประสิทธิภาพที่ดีกว่า

### Machine Types
Machine types ที่แนะนำสำหรับ workloads ต่างๆ:

- **Development**: `e2-standard-2` (2 vCPU, 8 GB)
- **Production**: `e2-standard-4` (4 vCPU, 16 GB)
- **High Performance**: `n2-standard-8` (8 vCPU, 32 GB)

### Networking
- ใช้ VPC-native clusters เพื่อ networking ที่ดีกว่า
- กำหนดค่า Cloud NAT สำหรับ private clusters
- ใช้ Cloud Armor สำหรับการป้องกัน DDoS

### ความปลอดภัย
- เปิดใช้งาน Binary Authorization
- ใช้ GKE Sandbox สำหรับการแยก pod
- กำหนดค่า Pod Security Standards
- ใช้ Private GKE clusters สำหรับ production

## ตัวเลือกฐานข้อมูล

### Internal PostgreSQL (เริ่มต้น)
- ดีสำหรับ development และ testing
- Scalability จำกัด
- ไม่มีการสำรองข้อมูลอัตโนมัติ

### Cloud SQL for PostgreSQL (แนะนำสำหรับ Production)
- Managed service
- การสำรองข้อมูลอัตโนมัติ
- High availability
- ประสิทธิภาพที่ดีกว่า
- การอัปเดตอัตโนมัติ

ตัวอย่างการเชื่อมต่อ Cloud SQL:
```yaml
airflow:
  config:
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://user:pass@/dbname?host=/cloudsql/project:region:instance
```

## การตั้งค่า Monitoring

### Prometheus + Grafana
1. ติดตั้ง Prometheus operator
2. กำหนดค่า ServiceMonitor สำหรับ Airflow
3. Import Airflow Grafana dashboards

### Google Cloud Monitoring
1. เปิดใช้งาน GKE monitoring
2. กำหนดค่า log aggregation
3. ตั้งค่า custom metrics

## กลยุทธ์การสำรองข้อมูล

### Database Backups
- ใช้การสำรองข้อมูลอัตโนมัติของ Cloud SQL
- Export metadata database เป็นประจำ
- ทดสอบขั้นตอนการ restore

### DAG Backups
- ใช้ Git สำหรับ version control
- Git-sync อัตโนมัติ
- สำรองข้อมูล repository เป็นประจำ

### Configuration Backups
- เก็บ Helm values ใน Git
- จัดทำเอกสารการกำหนดค่าแบบ custom
- รักษาประวัติการ deployment

## การปรับแต่งประสิทธิภาพ

### Scheduler Performance
```yaml
scheduler:
  replicas: 2
  resources:
    requests:
      cpu: "2000m"
      memory: "4Gi"
```

### Webserver Performance
```yaml
webserver:
  replicas: 2
  resources:
    requests:
      cpu: "1000m"
      memory: "2Gi"
```

### Database Optimization
- กำหนดค่า connection pooling
- ปรับแต่งประสิทธิภาพ query
- บำรุงรักษาฐานข้อมูลเป็นประจำ
- ตรวจสอบ slow queries

## การผสานรวมกับ CI/CD

### ตัวอย่าง GitHub Actions
```yaml
name: Deploy DAGs
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Deploy to GKE
        run: |
          gcloud container clusters get-credentials airflow-cluster
          kubectl cp dags/ airflow-webserver:/opt/airflow/dags/
```

### ตัวอย่าง GitLab CI
```yaml
deploy:
  stage: deploy
  script:
    - gcloud container clusters get-credentials airflow-cluster
    - kubectl cp dags/ airflow-webserver:/opt/airflow/dags/
  only:
    - main
```

## ปัญหาทั่วไปและวิธีแก้ไข

### ปัญหา: Pods ติดอยู่ใน Pending
**วิธีแก้**: ตรวจสอบทรัพยากร node เพิ่มขนาด cluster

### ปัญหา: Database connection timeout
**วิธีแก้**: ตรวจสอบ network policies ตรวจสอบ database credentials

### ปัญหา: DAGs ไม่ปรากฏ
**วิธีแก้**: ตรวจสอบสิทธิ์ DAG folder ตรวจสอบการกำหนดค่า git-sync

### ปัญหา: การใช้ memory สูง
**วิธีแก้**: เพิ่มทรัพยากร ปรับแต่งการ parse DAG

## Development Workflow

1. พัฒนา DAGs ในเครื่องโดยใช้ Docker
2. ทดสอบใน development environment
3. Code review และอนุมัติ
4. Deploy ไปยัง staging
5. ตรวจสอบและ validate
6. Deploy ไปยัง production

## ลิงก์ที่เป็นประโยชน์

- [Airflow 3 Migration Guide](https://airflow.apache.org/docs/apache-airflow/stable/upgrading-to-3.html)
- [Kubernetes Executor](https://airflow.apache.org/docs/apache-airflow/stable/executor/kubernetes.html)
- [GKE Best Practices](https://cloud.google.com/kubernetes-engine/docs/best-practices)
