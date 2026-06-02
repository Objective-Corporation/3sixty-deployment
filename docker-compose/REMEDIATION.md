# 3Sixty Docker Infrastructure Remediation Plan

**Assessment Date**: March 18, 2026  
**Last Updated**: May 14, 2026  
**Reviewer**: Docker Infrastructure Specialist  
**Overall Status**: Development-Ready | Not Production-Ready

---

## Executive Summary

The 3Sixty deployment infrastructure demonstrates good development practices but requires significant hardening for production use. Critical security vulnerabilities, missing health checks, and lack of resource management need immediate attention.

**Production Readiness Score**: 4.5/10

---

## 🔴 Critical Security Issues

### 1. Hardcoded Default Credentials

**Severity**: CRITICAL  
**Risk**: Unauthorized access to databases and messaging systems

**Current State**:

```bash
# sample.env files contain weak defaults
MONGO_INITDB_ROOT_PASSWORD=dbpassword
RABBITMQ_PASSWORD=guest
SCIM_PASSWORD=changeit
```

**Remediation**:

- ✅ COMPLETED: Created `.env.sample` with `CHANGEME_*` placeholders
- ✅ COMPLETED: Centralised all service config into single `.env.sample`
- ✅ COMPLETED: Removed real API key and token committed in old sample files
- 🔲 TODO: Implement HashiCorp Vault integration for production secrets
- 🔲 TODO: Add pre-commit hooks to prevent credential commits
- 🔲 TODO: Rotate all default credentials in existing deployments

**Timeline**: Immediate  
**Effort**: 2 hours

---

### 2. MongoDB Exposed on Host Network

**Severity**: HIGH  
**Risk**: Database accessible from host network without proper authentication

**Current State**:

```yaml
mongo:
  ports:
    - "27017:27017"  # Exposed to host
```

**Remediation**:

- 🔲 TODO: Remove port mapping for production deployments
- 🔲 TODO: Use Docker network isolation only
- 🔲 TODO: For dev/debugging, use `docker exec` instead of host ports
- 🔲 TODO: Implement firewall rules if host exposure required

**Timeline**: Week 1  
**Effort**: 1 hour

---

### 3. OpenSearch Security Disabled for Local Dev

**Severity**: HIGH (production) / Acceptable (local dev)  
**Risk**: Unprotected data access if exposed to untrusted networks

**Current State**:

```yaml
opensearch:
  environment:
    DISABLE_SECURITY_PLUGIN: "true"   # local dev only
```

OpenSearch is now the preferred search engine (Elasticsearch is legacy/disabled by default).
The security plugin is disabled for local development convenience. Elasticsearch host ports have
been remapped to 19200/19300 in `docker-compose.elasticsearch.yaml` to avoid clashing with
OpenSearch on 9200/9300.

**Remediation**:

- 🔲 TODO: Enable OpenSearch security plugin for production (`DISABLE_SECURITY_PLUGIN: "false"`)
- 🔲 TODO: Set strong `OPENSEARCH_INITIAL_ADMIN_PASSWORD` and reference from `.env`
- 🔲 TODO: Configure TLS for OpenSearch cluster communication
- 🔲 TODO: Remove host port bindings (9200/9300) for production deployments

**Timeline**: Week 1  
**Effort**: 3 hours

---

### 4. Vault Dev Mode in Production

**Severity**: CRITICAL (if used in production)  
**Risk**: Data loss, unauthorized access with root token

**Current State**:

```yaml
vault:
  environment:
    VAULT_DEV_ROOT_TOKEN_ID: root  # Hardcoded
  command: server -dev             # In-memory only
```

**Remediation**:

- 🔲 TODO: Configure Vault in production mode with persistent storage
- 🔲 TODO: Implement proper unsealing mechanism
- 🔲 TODO: Use auto-unseal with cloud KMS
- 🔲 TODO: Remove dev mode from all deployment paths
- 🔲 TODO: Document secret migration from dev to prod Vault

**Timeline**: Week 2  
**Effort**: 8 hours

---

### 5. Self-Signed Certificates

**Severity**: MEDIUM  
**Risk**: MITM attacks, certificate trust issues

**Current State**:

- Self-signed certificates generated locally
- No certificate validation in documentation
- Manual certificate management

**Remediation**:

- 🔲 TODO: Integrate Let's Encrypt for automatic SSL/TLS
- 🔲 TODO: Use cert-manager for Kubernetes deployments
- 🔲 TODO: Document certificate rotation procedures
- 🔲 TODO: Add certificate expiration monitoring

**Timeline**: Week 2  
**Effort**: 4 hours

---

## ⚠️ High Priority Configuration Issues

### 6. Missing Health Checks

**Severity**: HIGH  
**Impact**: Race conditions, services receiving traffic before ready

**Remediation**:

- ✅ COMPLETED: Added health checks to all services
- 🔲 TODO: Test health check endpoints in staging
- 🔲 TODO: Configure health check monitoring alerts

**Timeline**: COMPLETED  
**Effort**: 3 hours

---

### 7. No Resource Limits

**Severity**: HIGH  
**Impact**: Resource exhaustion, noisy neighbor problems

**Remediation**:

- ✅ COMPLETED: Added CPU and memory limits to all services
- 🔲 TODO: Performance test under resource constraints
- 🔲 TODO: Tune limits based on actual usage metrics
- 🔲 TODO: Add resource monitoring dashboard

**Timeline**: COMPLETED  
**Effort**: 2 hours

---

### 8. Version Inconsistencies

**Severity**: MEDIUM  
**Impact**: Compatibility issues, unclear canonical configuration

**Current State**:

- `docker-compose.yaml`: `objective3sixty:5.2.1`, `mongo:8.0.11` (current)
- Legacy backup files reference older versions — remove or update

**Remediation**:

- 🔲 TODO: Remove or archive `docker-compose.yaml.backup` and `docker-compose.afs.yaml.backup`
- 🔲 TODO: Use environment variables for version pinning
- 🔲 TODO: Document version compatibility matrix in solution specification
- 🔲 TODO: Implement version testing in CI/CD

**Timeline**: Week 1  
**Effort**: 2 hours

---

### 9. Missing Logging Configuration

**Severity**: MEDIUM  
**Impact**: Disk space exhaustion, difficult troubleshooting

**Remediation**:

- ✅ COMPLETED: Added JSON file logging with rotation to all services
- 🔲 TODO: Configure log aggregation (Loki or OpenSearch ingest)
- 🔲 TODO: Set appropriate log levels per environment
- 🔲 TODO: Implement structured logging

**Timeline**: Week 2  
**Effort**: 4 hours

---

### 10. Nginx Security Headers Missing

**Severity**: MEDIUM  
**Impact**: Vulnerable to clickjacking, XSS, MIME sniffing

**Remediation**:

- ✅ COMPLETED: Added security headers to `nginx/nginx.conf`
- 🔲 TODO: Test CSP headers with application
- 🔲 TODO: Implement HSTS preload
- 🔲 TODO: Add rate limiting

**Timeline**: COMPLETED  
**Effort**: 1 hour

---

## 🟡 Medium Priority Improvements

### 11. Inconsistent Restart Policies

**Current State**:

- `unless-stopped`: nginx, mongo, opensearch, ollama
- Review all services for consistent policy

**Remediation**:

- 🔲 TODO: Standardize restart policies per environment
- 🔲 TODO: Document restart policy rationale
- 🔲 TODO: Implement circuit breaker for rapid failures

**Timeline**: Week 2  
**Effort**: 1 hour

---

### 12. Ollama Model Pulling Performance

**Current State**:

```yaml
command: >
  "ollama serve & sleep 5 && ollama pull mxbai-embed-large && ollama pull gemma2:2b && wait"
```

**Issues**:

- Models are pulled on first start (slow) but cached in `ollama_data` volume on subsequent starts
- Fixed 5-second sleep before pull (brittle)
- No health check for model availability

**Remediation**:

- 🔲 TODO: Create custom Ollama image with models baked in for faster cold starts
- 🔲 TODO: Use init containers or wait-for pattern instead of fixed sleep
- 🔲 TODO: Add health check for model readiness

**Timeline**: Week 3  
**Effort**: 3 hours

---

### 13. MongoDB Init Script Improvements

**Current State**:

```bash
export MONGO_INITDB_DATABASE=${MONGO_INITDB_DATABASE:="dbtest"}
```

**Issues**:

- Silent fallback to defaults
- No validation of required variables

**Remediation**:

- 🔲 TODO: Fail fast if required env vars missing
- 🔲 TODO: Add index creation for performance
- 🔲 TODO: Implement idempotent script execution

**Timeline**: Week 3  
**Effort**: 2 hours

---

### 14. CORS Wildcard in RAG Service

**Current State**:

```bash
CORS_ALLOW_ORIGINS=*   # in .env.sample
```

**Remediation**:

- 🔲 TODO: Restrict to specific domain in production (e.g. `https://threesixty.objective.com`)
- 🔲 TODO: Document CORS requirements per deployment environment

**Timeline**: Week 1  
**Effort**: 30 minutes

---

## 🟢 Low Priority Enhancements

### 15. Monitoring Stack Implementation

**Remediation**:

- ✅ COMPLETED: Created `docker-compose.monitoring.yaml` (Prometheus + Grafana)
- 🔲 TODO: Configure Grafana dashboards
- 🔲 TODO: Add alerting rules
- 🔲 TODO: Integrate with PagerDuty/Opsgenie

**Timeline**: Week 4  
**Effort**: 8 hours

---

### 16. Image Optimization

**Remediation**:

- 🔲 TODO: Audit ECR image sizes
- 🔲 TODO: Implement multi-stage builds
- 🔲 TODO: Use distroless base images where applicable
- 🔲 TODO: Document image optimization guidelines

**Timeline**: Week 4  
**Effort**: 16 hours

---

### 17. Backup and Disaster Recovery

**Remediation**:

- 🔲 TODO: Implement automated MongoDB backups
- 🔲 TODO: Document restore procedures
- 🔲 TODO: Test disaster recovery runbook
- 🔲 TODO: Configure backup monitoring

**Timeline**: Week 4  
**Effort**: 12 hours

---

### 18. Network Optimization

**Current State**: Basic bridge network

**Remediation**:

- 🔲 TODO: Evaluate overlay network for multi-host deployments
- 🔲 TODO: Implement network segmentation
- 🔲 TODO: Add network policies for zero-trust
- 🔲 TODO: Configure MTU for performance

**Timeline**: Month 2  
**Effort**: 6 hours

---

## 📊 Remediation Timeline

### Week 1 (Immediate — Security Focus)

- [ ] Change all default passwords (**2h**)
- [ ] Remove MongoDB host port mapping (**1h**)
- [ ] Enable OpenSearch security plugin (**3h**)
- [ ] Standardize image versions / remove backup files (**2h**)
- [ ] Restrict CORS in production (**0.5h**)

**Total Effort**: ~9 hours

---

### Week 2 (High Priority — Production Readiness)

- [ ] Configure Vault production mode (**8h**)
- [ ] Implement Let's Encrypt integration (**4h**)
- [ ] Add log aggregation (**4h**)
- [ ] Standardize restart policies (**1h**)
- [ ] Test health checks in staging (**3h**)

**Total Effort**: 20 hours

---

### Week 3 (Medium Priority — Performance)

- [ ] Optimize Ollama image (**3h**)
- [ ] Improve MongoDB init script (**2h**)
- [ ] Performance test with resource limits (**4h**)
- [ ] Tune resource allocations (**3h**)

**Total Effort**: 12 hours

---

### Week 4 (Low Priority — Operations)

- [ ] Configure Grafana dashboards (**4h**)
- [ ] Set up alerting rules (**4h**)
- [ ] Implement automated backups (**8h**)
- [ ] Document disaster recovery (**4h**)
- [ ] Audit and optimize images (**16h**)

**Total Effort**: 36 hours

---

## 🎯 Success Criteria

### Security

- [ ] All default passwords changed to strong, unique values
- [ ] No services exposed to host network unnecessarily
- [ ] OpenSearch security plugin enabled and tested
- [ ] Vault running in production mode with auto-unseal
- [ ] SSL/TLS certificates from trusted CA

### Reliability

- [ ] Health checks passing for all services
- [ ] Resource limits preventing service exhaustion
- [ ] Restart policies appropriate for service criticality
- [ ] Zero failed deployments due to configuration issues

### Observability

- [ ] Prometheus metrics exported from all services
- [ ] Grafana dashboards showing key metrics
- [ ] Log aggregation configured and tested
- [ ] Alerts configured for critical conditions

### Operations

- [ ] Automated backups running and verified
- [ ] Disaster recovery procedures documented and tested
- [ ] Deployment playbooks updated
- [ ] Team trained on new procedures

---

## 📋 Verification Checklist

### Pre-Production Deployment

- [ ] All critical and high priority items completed
- [ ] Security scan passed (no critical/high vulnerabilities)
- [ ] Load testing completed successfully
- [ ] Disaster recovery tested
- [ ] Monitoring and alerting operational
- [ ] Team training completed
- [ ] Documentation reviewed and updated
- [ ] Runbooks validated

### Production Readiness Gates

- [ ] Change advisory board approval
- [ ] Security team sign-off
- [ ] Operations team acceptance
- [ ] Disaster recovery plan approved
- [ ] Rollback plan documented
- [ ] On-call rotation established

---

## 📚 Reference Documentation

### Security Standards

- OWASP Docker Security Cheat Sheet
- CIS Docker Benchmark v1.6.0
- NIST Container Security Guide

### Best Practices

- Docker Production Best Practices
- 12-Factor App Methodology
- Site Reliability Engineering (Google)

### Tools

- Docker Scout (vulnerability scanning)
- Trivy (container scanning)
- Checkov (IaC security)
- OWASP ZAP (application security)

---

## 📞 Contacts

**Security Issues**: security@objective.com  
**Infrastructure Support**: devops@objective.com  
**Emergency On-Call**: +61 XXX XXX XXX

---

**Document Version**: 1.1  
**Last Updated**: May 14, 2026  
**Next Review**: June 14, 2026
