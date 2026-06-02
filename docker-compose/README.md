# 3Sixty Local Development

This repository contains everything needed to run all 3Sixty services locally via Docker Compose.

For the full architecture, technology rationale, and platform-migration reference, see [docs/solution-specification.md](../docs/solution-specification.md).

---

## Prerequisites

- **Docker** ≥ 20.10 with Docker Compose v2
- **[AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)** ≥ 2
- **8GB+ RAM** available (OpenSearch + Ollama are memory-intensive)
- **20GB+ disk space**
- **[ngrok](https://ngrok.com/downloads)** or **[cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/)** (optional — required for SCIM and Microsoft Copilot Agent)

---

## Quick Start

```bash
make aws-login          # Authenticate to AWS ECR
make env-create         # Create .env from .env.sample
# Edit .env — fill in all CHANGEME values
make certs              # Generate self-signed SSL cert for nginx
make start              # Start all core services
make health             # Wait ~90s then check all services are healthy
```

See [QUICKSTART.md](QUICKSTART.md) for the full step-by-step guide.

---

## Configuration

All services share a single environment file:

```text
.env.sample   →   copy to   →   .env   (gitignored, holds real values)
```

`make env-create` performs the copy. Edit `.env` and replace every `CHANGEME_*` value before starting.

### Minimum required values

| Variable | Where to get it |
| --- | --- |
| `MONGO_INITDB_ROOT_PASSWORD` | Generate: `openssl rand -base64 32` |
| `RABBITMQ_DEFAULT_PASS` | Generate: `openssl rand -base64 32` |
| `CLIENT_ID` | Azure Portal → App Registrations |
| `TENANT_ID` | Azure Portal → App Registrations |
| `CLIENT_SECRET` | Azure Portal → App Registrations |
| `OPENAI_API_KEY` | LLM provider, or `no-key` for local Ollama |
| `BEARER_TOKEN` | Any strong random string |

### Remote agent (configure after first login to Admin UI)

| Variable | Notes |
| --- | --- |
| `REMOTE_AGENT_TOKEN` | Create the agent in Admin UI, then paste token here |
| `REMOTE_AGENT_NAME` | Must match the name configured in Admin UI |

### LLM provider

The `.env` file contains four commented provider blocks (Objective Foundation API, Gemini, OpenAI, Ollama). Uncomment one block and comment out the rest to select your provider.

---

## SSL Certificates

Nginx requires a certificate and key for TLS termination.

```bash
# Generate self-signed (local dev only)
make certs
```

For trusted certificates, place your `.cer` files in `certs/` and mount the folder into the admin container:

```yaml
services:
  threesixty-admin:
    volumes:
      - ./certs:/opt/certs:ro
```

The container entrypoint will import any `.cer` files found there into the JVM truststore via `keytool`.

### Line endings (Windows)

Shell scripts (`mongodb/init-mongo.sh`) must use Unix LF line endings, not Windows CRLF. In VS Code, click the line-ending indicator in the status bar and select **LF**.

---

## Access URLs

| Service | URL | Notes |
| --- | --- | --- |
| Admin UI | <https://localhost/3sixty-admin/> | First login sets up admin account |
| Discovery UI | <https://localhost/3sixty-discovery/> | Azure AD SSO |
| OpenSearch Dashboards | <https://localhost/opensearch-dashboard/> | Also direct: <http://localhost:15601> |
| RabbitMQ Management | <http://localhost:15672> | Credentials from `.env` |
| 3sixty-rag API | <http://localhost:5000> | RAG service direct |
| Kibana (optional) | <https://localhost/kibana> | Requires `make elasticsearch-start` |

---

## Optional Services

```bash
make opensearch-start      # Start OpenSearch + Dashboards independently
make monitoring-start      # Prometheus + Grafana (http://localhost:3001)
make vault-start           # HashiCorp Vault dev mode (http://localhost:8200)
make oi-agent-start        # OI Remote Agent (configure REMOTE_AGENT_TOKEN first)
make elasticsearch-start   # Legacy Elasticsearch + Kibana (ports 19200/5601)
```

---

## Common Operations

```bash
make help          # Full command reference
make logs          # Tail all service logs
make logs-admin    # Admin service logs only
make health        # Container health status
make ps            # Running containers
make stop          # Stop all services
make restart       # Restart all services
make clean         # Stop and remove volumes (DESTRUCTIVE)
make pull          # Pull latest images from ECR
make update        # Pull and restart
```

---

## Public URL for SCIM and Microsoft Copilot Agent

Microsoft Entra ID (Azure AD) requires a publicly accessible HTTPS URL to push SCIM user/group sync events. The Microsoft Copilot remote agent similarly needs external reachability. For local development, use a tunnel:

```bash
# Option 1 — ngrok
ngrok http 443
# Generates: https://abc123.ngrok.io → https://localhost

# Option 2 — Cloudflare Tunnel (persistent subdomain)
cloudflared tunnel --url https://localhost
```

Set the resulting public URL in the Admin UI OAuth2 and SCIM configuration.

---

## Troubleshooting

### Services won't start

```bash
make aws-verify        # Check ECR authentication
make logs              # Check for startup errors
docker info            # Verify Docker is running
```

### Can't access via HTTPS

```bash
make certs             # Regenerate certificates
docker compose restart nginx
```

### Discovery service login fails after OAuth2 setup

OAuth2 state can get out of sync after configuration changes. Restart all services:

```bash
make restart
```

Then verify `CLIENT_ID`, `TENANT_ID`, `CLIENT_SECRET` in `.env` and that the OAuth2 callback URL matches the public URL used during Admin UI setup.

### MongoDB connection errors

```bash
docker exec mongo mongosh --eval "db.adminCommand('ping')"
grep MONGO .env
```

### OpenSearch won't start

```bash
# Check vm.max_map_count (Linux/WSL2)
sysctl vm.max_map_count
# If < 262144:
sudo sysctl -w vm.max_map_count=262144
```
