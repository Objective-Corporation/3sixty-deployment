# 3Sixty Quick Start Guide

Get 3Sixty running locally in 5 minutes.

---

## Prerequisites

- Docker Desktop installed and running
- AWS CLI v2 configured
- 8GB+ RAM available
- 20GB+ disk space

---

## Quick Setup

### 1. Configure AWS Access

```bash
# Configure AWS credentials
aws configure

# Login to ECR
make aws-login

# Verify authentication
make aws-verify
```

### 2. Configure Environment

```bash
# Copy sample environment file
cp .env.sample .env

# Edit .env with your values (minimum required):
# - MONGO_INITDB_ROOT_PASSWORD
# - RABBITMQ_DEFAULT_PASSWORD
# - CLIENT_ID (Azure AD)
# - TENANT_ID (Azure AD)
# - CLIENT_SECRET (Azure AD)
```

### 3. Generate SSL Certificates

```bash
# Generate self-signed certs for local development
make certs
```

### 4. Start Services

```bash
# Start all core services
make start

# Wait for services to be healthy (60-90 seconds)
make health
```

### 5. Access Applications

| Service | URL | Credentials |
|---------|-----|-------------|
| **Admin UI** | https://localhost/3sixty-admin/ | Configure in Admin during first login |
| **Discovery UI** | https://localhost/3sixty-discovery/ | Azure AD SSO |
| **OpenSearch Dashboard** | https://localhost/opensearch-dashboard/ | admin / admin |
| **RabbitMQ Management** | http://localhost:15672 | See .env file |
| **Kibana** (optional) | https://localhost/kibana | Requires `make elasticsearch-start` |

---

## Common Commands

```bash
# View logs
make logs                    # All services
make logs-admin             # Admin service only
make logs-discovery         # Discovery service only

# Service management
make stop                   # Stop all services
make restart               # Restart all services
make clean                 # Stop and remove volumes (DESTRUCTIVE)

# Health checks
make health                # Check service health
make ps                    # View running containers

# Updates
make pull                  # Pull latest images
make update                # Pull images and restart

# Monitoring (optional)
make monitoring-start      # Start Prometheus + Grafana
make monitoring-stop       # Stop monitoring stack

# Elasticsearch + Kibana (optional)
make elasticsearch-start   # Start Elasticsearch + Kibana
make elasticsearch-stop    # Stop Elasticsearch + Kibana
```

---

## Troubleshooting

### Services won't start
```bash
# Check Docker is running
docker info

# Check logs for errors
make logs

# Verify AWS authentication
make aws-verify
```

### Can't access via HTTPS
```bash
# Verify nginx is running
docker ps | grep nginx

# Regenerate certificates
make certs

# Restart nginx
docker compose restart nginx
```

### MongoDB connection errors
```bash
# Check MongoDB is healthy
docker exec mongo mongosh --eval "db.adminCommand('ping')"

# Verify environment variables
cat .env | grep MONGO
```

### Discovery service login fails
```bash
# Verify Azure AD configuration
cat .env | grep CLIENT

# Restart all services to sync OAuth state
make restart
```

---

## What's Next?

1. **Configure OAuth2** in Admin UI for Discovery service
2. **Create Remote Agent** in Admin UI and configure `.env.oi-agent`
3. **Start monitoring stack**: `make monitoring-start`
4. **Review security settings**: See [REMEDIATION.md](REMEDIATION.md)

---

## Getting Help

- **Documentation**: [README.md](README.md)
- **Issues**: Review [REMEDIATION.md](REMEDIATION.md)
- **Monitoring**: Access Grafana at http://localhost:3001 (after `make monitoring-start`)

---

**Pro Tip**: Run `make help` to see all available commands!
