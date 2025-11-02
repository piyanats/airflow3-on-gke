# Development Notes

## Airflow 3 Key Changes

Apache Airflow 3.0 includes several important changes from version 2.x:

### Breaking Changes
- Python 3.8+ required (3.11 recommended)
- Removed deprecated features from 2.x
- Updated database schema
- Changes to operator interfaces
- Updated authentication mechanisms

### New Features
- Improved Kubernetes executor
- Better DAG serialization
- Enhanced task execution
- Improved UI/UX
- Better observability

## GKE Specific Considerations

### Storage Classes
- `standard`: Standard persistent disk (HDD)
- `standard-rwo`: Standard persistent disk (ReadWriteOnce)
- `premium-rwo`: SSD persistent disk (ReadWriteOnce)

For production, use `premium-rwo` for better performance.

### Machine Types
Recommended machine types for different workloads:

- **Development**: `e2-standard-2` (2 vCPU, 8 GB)
- **Production**: `e2-standard-4` (4 vCPU, 16 GB)
- **High Performance**: `n2-standard-8` (8 vCPU, 32 GB)

### Networking
- Use VPC-native clusters for better networking
- Configure Cloud NAT for private clusters
- Use Cloud Armor for DDoS protection

### Security
- Enable Binary Authorization
- Use GKE Sandbox for pod isolation
- Configure Pod Security Standards
- Use Private GKE clusters for production

## Database Options

### Internal PostgreSQL (Default)
- Good for development and testing
- Limited scalability
- No automatic backups

### Cloud SQL for PostgreSQL (Recommended for Production)
- Managed service
- Automatic backups
- High availability
- Better performance
- Automatic updates

Example Cloud SQL connection:
```yaml
airflow:
  config:
    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://user:pass@/dbname?host=/cloudsql/project:region:instance
```

## Monitoring Setup

### Prometheus + Grafana
1. Install Prometheus operator
2. Configure ServiceMonitor for Airflow
3. Import Airflow Grafana dashboards

### Google Cloud Monitoring
1. Enable GKE monitoring
2. Configure log aggregation
3. Set up custom metrics

## Backup Strategy

### Database Backups
- Use Cloud SQL automated backups
- Export metadata database regularly
- Test restore procedures

### DAG Backups
- Use Git for version control
- Automated Git-sync
- Regular repository backups

### Configuration Backups
- Store Helm values in Git
- Document custom configurations
- Maintain deployment history

## Performance Tuning

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
- Configure connection pooling
- Optimize query performance
- Regular database maintenance
- Monitor slow queries

## CI/CD Integration

### GitHub Actions Example
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

### GitLab CI Example
```yaml
deploy:
  stage: deploy
  script:
    - gcloud container clusters get-credentials airflow-cluster
    - kubectl cp dags/ airflow-webserver:/opt/airflow/dags/
  only:
    - main
```

## Common Issues and Solutions

### Issue: Pods stuck in Pending
**Solution**: Check node resources, increase cluster size

### Issue: Database connection timeout
**Solution**: Check network policies, verify database credentials

### Issue: DAGs not appearing
**Solution**: Check DAG folder permissions, verify git-sync configuration

### Issue: High memory usage
**Solution**: Increase resources, optimize DAG parsing

## Development Workflow

1. Develop DAGs locally using Docker
2. Test in development environment
3. Code review and approval
4. Deploy to staging
5. Monitor and validate
6. Deploy to production

## Useful Links

- [Airflow 3 Migration Guide](https://airflow.apache.org/docs/apache-airflow/stable/upgrading-to-3.html)
- [Kubernetes Executor](https://airflow.apache.org/docs/apache-airflow/stable/executor/kubernetes.html)
- [GKE Best Practices](https://cloud.google.com/kubernetes-engine/docs/best-practices)
