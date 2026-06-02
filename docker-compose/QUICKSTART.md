# 3Sixty Quick Start Guide

Get 3Sixty running locally in 5 minutes.

---

## Prerequisites

- Docker Desktop installed and running
- AWS CLI v2 configured
- 8GB+ RAM available
- 20GB+ disk space
- Chocolatey and  Makefile
- Git Bash

---
Chocolatey and Makefile Install

Set-ExecutionPolicy Bypass -Scope Process -Force
iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
choco

choco install make
make --version


---

Git Bash Install

winget install --id Git.Git -e --source winget

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
cp .env.sample .env          # Linux/macOS
copy .env.sample .env         # Windows

# Edit .env with your values (minimum required):
# - MONGO_INITDB_ROOT_PASSWORD   (generate: openssl rand -base64 32)
# - RABBITMQ_DEFAULT_PASS        (generate: openssl rand -base64 32)
# - CLIENT_ID                    (Azure Portal → App Registrations)
# - TENANT_ID                    (Azure Portal → App Registrations)
# - CLIENT_SECRET                (Azure Portal → App Registrations)
# - OPENAI_API_KEY               (LLM provider, or leave as no-key for Ollama)
# - BEARER_TOKEN                 (any strong random string)
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

| Service | URL | Notes |
| --- | --- | --- |
| **Admin UI** | <https://localhost/3sixty-admin/> | Configure during first login |
| **Discovery UI** | <https://localhost/3sixty-discovery/> | Azure AD SSO |
| **OpenSearch Dashboards** | <https://localhost/opensearch-dashboard/> | Also direct: <http://localhost:15601> |
| **RabbitMQ Management** | <http://localhost:15672> | Credentials from `.env` |
| **Kibana** (optional) | <https://localhost/kibana> | Requires `make elasticsearch-start` |

---

## Common Commands

```bash
# View logs
make logs                    # All services
make logs-admin              # Admin service only
make logs-discovery          # Discovery service only
make logs-opensearch         # OpenSearch only

# Service management
make stop                    # Stop all services
make restart                 # Restart all services
make clean                   # Stop and remove volumes (DESTRUCTIVE)

# Health checks
make health                  # Check service health
make ps                      # View running containers

# Updates
make pull                    # Pull latest images
make update                  # Pull images and restart

# OpenSearch (preferred search engine — runs as part of core stack)
make opensearch-start        # Start OpenSearch + Dashboards independently
make opensearch-stop         # Stop OpenSearch + Dashboards

# Monitoring (optional)
make monitoring-start        # Start Prometheus + Grafana
make monitoring-stop         # Stop monitoring stack

# Elasticsearch + Kibana (optional — legacy, prefer OpenSearch)
make elasticsearch-start     # Start on remapped ports 19200/5601
make elasticsearch-stop      # Stop Elasticsearch + Kibana
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
grep MONGO .env
```

### Discovery service login fails

```bash
# Verify Azure AD configuration
grep CLIENT .env

# Restart all services to sync OAuth state
make restart
```

### OpenSearch won't start

```bash
# Linux/WSL2: check and set vm.max_map_count
sysctl vm.max_map_count
sudo sysctl -w vm.max_map_count=262144
```

---

## What's Next?

1. **Configure OAuth2** in Admin UI for the Discovery service
2. **Create Remote Agent** in Admin UI, then update `REMOTE_AGENT_TOKEN` and `REMOTE_AGENT_NAME` in `.env` and run `make oi-agent-start`
3. **Select your LLM provider** — edit the provider block in `.env` (Objective Foundation API, Gemini, OpenAI, or local Ollama)
4. **Start monitoring stack**: `make monitoring-start`
5. **Review security settings**: see [REMEDIATION.md](REMEDIATION.md)

---

## Getting Help

- **Full documentation**: [README.md](README.md)
- **Architecture & spec**: [docs/solution-specification.md](../docs/solution-specification.md)
- **Security issues**: [REMEDIATION.md](REMEDIATION.md)
- **Monitoring**: Grafana at <http://localhost:3001> (after `make monitoring-start`)

---

**Run `make help` to see all available commands.**
