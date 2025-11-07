# Security Fixes and Improvements Applied

## Date: 2025-11-07

This document outlines all the critical security fixes and improvements that have been applied to the Airflow 3 on GKE project.

## Critical Security Fixes

### 1. Fixed Hardcoded Secrets (CRITICAL)
**Files Modified:**
- `airflow-helm/templates/secret.yaml`
- `airflow-helm/values.yaml`

**Changes:**
- Removed hardcoded fernet key and webserver secret key
- Now requires these values to be set in values.yaml
- Added clear instructions for generating secure keys
- Helm chart will fail with descriptive error if secrets are not provided

**Generate Secrets:**
```bash
# Generate Fernet Key
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"

# Generate Webserver Secret
openssl rand -base64 32
```

### 2. Fixed Hardcoded Database Password (CRITICAL)
**Files Modified:**
- `airflow-helm/values.yaml`
- `airflow-helm/templates/postgres-deployment.yaml`
- `airflow-helm/templates/postgres-secret.yaml` (NEW)

**Changes:**
- Changed default PostgreSQL password from "airflow" to require configuration
- Moved PostgreSQL password to Kubernetes Secret
- Added clear warning in values.yaml about changing passwords

### 3. Fixed Hardcoded Admin Credentials (CRITICAL)
**Files Modified:**
- `airflow-helm/templates/webserver-deployment.yaml`
- `airflow-helm/values.yaml`

**Changes:**
- Admin username and password now configurable via values.yaml
- Added admin user configuration section with clear warnings
- Init container now uses templated credentials

## High-Priority Bug Fixes

### 4. Fixed RBAC Scope Issue
**Files Modified:**
- `airflow-helm/templates/rbac.yaml`

**Changes:**
- Changed from `Role` to `ClusterRole`
- Changed from `RoleBinding` to `ClusterRoleBinding`
- Added namespace to ClusterRoleBinding subjects
- Added additional permissions for pod/status and configmaps
- This fixes KubernetesExecutor cross-namespace worker pod creation

### 5. Fixed Duplicate UV Installation in Dockerfile
**Files Modified:**
- `docker/Dockerfile`

**Changes:**
- Removed duplicate UV installation (was installed twice)
- Reduces build time and image size

### 6. Fixed Chart.Name vs Release.Name Issue
**Files Modified:** (All Helm templates updated)
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

**Changes:**
- Changed all resources to use `{{ .Release.Name }}` instead of `{{ .Chart.Name }}`
- Allows multiple Airflow releases in the same namespace
- Prevents resource name conflicts
- Added `release: {{ .Release.Name }}` label to all resources

### 7. Added Scheduler Readiness Probe
**Files Modified:**
- `airflow-helm/templates/scheduler-deployment.yaml`

**Changes:**
- Added readinessProbe for scheduler container
- Prevents traffic routing before scheduler is fully ready
- Uses same health check as liveness probe

## Medium-Priority Improvements

### 8. Added Resource Limits to Init Containers
**Files Modified:**
- `airflow-helm/templates/webserver-deployment.yaml`
- `airflow-helm/templates/scheduler-deployment.yaml`

**Changes:**
- Added CPU and memory limits to all init containers
- Prevents init containers from consuming excessive resources
- wait-for-db: 100m CPU / 128Mi memory (request), 200m / 256Mi (limit)
- init-db: 200m CPU / 256Mi memory (request), 500m / 512Mi (limit)

### 9. Added Database Connection Timeout
**Files Modified:**
- `airflow-helm/templates/webserver-deployment.yaml`
- `airflow-helm/templates/scheduler-deployment.yaml`

**Changes:**
- Added MAX_RETRIES (60 attempts = 5 minutes) to wait-for-db init containers
- Prevents infinite loops if database is misconfigured
- Provides clear error message on timeout

### 10. Added PostgreSQL Health Checks
**Files Modified:**
- `airflow-helm/templates/postgres-deployment.yaml`

**Changes:**
- Added livenessProbe using pg_isready
- Added readinessProbe using pg_isready
- Ensures PostgreSQL is healthy before accepting connections

### 11. Added PostgreSQL Security Context
**Files Modified:**
- `airflow-helm/templates/postgres-deployment.yaml`

**Changes:**
- Added pod security context
- Runs as non-root user (UID 999)
- Sets fsGroup for volume permissions
- Follows Kubernetes security best practices

## Files Created

### New Files:
1. `airflow-helm/templates/postgres-secret.yaml` - Kubernetes Secret for PostgreSQL password
2. `SECURITY_FIXES.md` - This document

## Deployment Notes

### BREAKING CHANGES:
⚠️ **IMPORTANT**: These changes introduce breaking changes that require configuration updates before deployment.

1. **Required Values** - You MUST set these in your values.yaml before deploying:
   ```yaml
   airflow:
     fernetKey: "<YOUR_GENERATED_FERNET_KEY>"
     webserverSecretKey: "<YOUR_GENERATED_SECRET>"
     adminUser:
       password: "<YOUR_ADMIN_PASSWORD>"  # Change from default

   postgresql:
     auth:
       password: "<YOUR_DB_PASSWORD>"  # Change from default
   ```

2. **Resource Name Changes** - All resources now use release name instead of chart name:
   - Old: `airflow-webserver`, `airflow-secret`, etc.
   - New: `<release-name>-webserver`, `<release-name>-secret`, etc.
   - If upgrading existing deployment, this may cause new resources to be created

3. **RBAC Changes** - ClusterRole/ClusterRoleBinding instead of Role/RoleBinding:
   - More permissions granted (cluster-wide)
   - May require additional RBAC permissions to deploy

### Migration from Old Version:

If you have an existing deployment, you should:

1. **Backup your current deployment**:
   ```bash
   kubectl get all -n <namespace> -o yaml > backup.yaml
   helm get values <release-name> -n <namespace> > old-values.yaml
   ```

2. **Generate new secrets**:
   ```bash
   # Fernet key
   python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"

   # Webserver secret
   openssl rand -base64 32

   # Database password
   openssl rand -base64 16
   ```

3. **Update your values.yaml** with the new required fields

4. **Consider a fresh install** rather than upgrade due to resource naming changes:
   ```bash
   # Uninstall old
   helm uninstall <release-name> -n <namespace>

   # Install new with updated values
   helm install <release-name> ./airflow-helm -f updated-values.yaml -n <namespace>
   ```

## Validation

To validate the Helm chart after these changes:

```bash
# Lint the chart
helm lint ./airflow-helm

# Dry-run to check for errors
helm install test-release ./airflow-helm \
  --dry-run \
  --debug \
  -f your-values.yaml

# Template to see generated YAML
helm template test-release ./airflow-helm -f your-values.yaml
```

## Security Checklist for Production

- [ ] Generated unique Fernet key
- [ ] Generated unique webserver secret key
- [ ] Changed admin password from default
- [ ] Changed PostgreSQL password from default
- [ ] Reviewed and limited RBAC permissions if needed
- [ ] Configured TLS/HTTPS via Ingress
- [ ] Enabled Cloud SQL for production database (disable bundled PostgreSQL)
- [ ] Configured GCS remote logging
- [ ] Set up Workload Identity for GCP access
- [ ] Configured resource limits appropriately
- [ ] Reviewed network policies
- [ ] Set up monitoring and alerting

## Additional Recommendations

While not implemented in this fix set, consider these for production:

1. **External Secrets Operator**: Integrate with GCP Secret Manager or similar
2. **Pod Security Standards**: Apply restrictive pod security policies
3. **Network Policies**: Implement network segmentation
4. **Image Scanning**: Scan container images for vulnerabilities
5. **Audit Logging**: Enable Kubernetes audit logs
6. **Backup Strategy**: Implement regular database backups
7. **Disaster Recovery**: Document and test DR procedures

## Testing

After applying these fixes, test:

1. Helm chart validation:
   ```bash
   helm lint ./airflow-helm
   ```

2. Deployment with proper secrets:
   ```bash
   helm install test ./airflow-helm -f test-values.yaml --dry-run
   ```

3. Check resource creation:
   ```bash
   kubectl get all -n <namespace>
   ```

4. Verify security:
   ```bash
   kubectl get secrets -n <namespace>
   kubectl describe pod <pod-name> -n <namespace>
   ```

## Summary

**Total Fixes Applied**: 11
- Critical Security: 3
- High-Priority Bugs: 4
- Medium-Priority: 4

All critical security vulnerabilities have been addressed. The project is now significantly more secure and production-ready.
