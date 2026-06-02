# 3Sixty Deployment — Solution Specification

**Version**: 1.0  
**Application Version**: 5.2.1  
**Last Updated**: 2026-05-14  
**Maintainer**: Objective Corporation

---

## 1. Purpose and Scope

This document is the authoritative reference for the 3Sixty deployment solution. It is written for:

- **Engineers and operators** deploying or maintaining the solution
- **AI agents** performing automated changes, upgrades, or migrations
- **Architects** evaluating technology choices or adapting the stack to a new container platform

The specification describes the complete solution architecture, every service's role and configuration, networking model, secrets handling, and the rationale behind key technology decisions. Where a technology is replaced, this document provides enough context to produce equivalent configuration for the replacement platform.

---

## 2. Solution Overview

3Sixty is an Objective Corporation enterprise content management and discovery platform. The deployment stack provides:

- **Content management** via the 3Sixty Admin webapp
- **Content discovery** via the 3Sixty Discovery webapp (Azure AD SSO)
- **AI-powered search and RAG** (Retrieval-Augmented Generation) via OpenSearch + Ollama + RAG service
- **User provisioning** via a SCIM 2.0 server (Microsoft Entra ID / Azure AD integration)
- **Remote agent capability** for extending indexing and search to remote document sources

The stack is deployed on two platforms:

| Platform | Location | Use Case |
|---|---|---|
| Docker Compose | `docker-compose/` | Local development, on-premises single-host |
| Kubernetes (Helm) | `helm/` | Production, AKS (Azure Kubernetes Service) |

---

## 3. Architecture Overview

```
                          ┌─────────────────────────────────────────────────────┐
                          │  NGINX (reverse proxy / TLS termination)             │
                          │  Ports: 80 (HTTP→HTTPS redirect), 443 (HTTPS)       │
                          └────┬──────────┬──────────┬────────────┬─────────────┘
                               │          │          │            │
                    /3sixty-admin  /3sixty-discovery  /scim/v2  /opensearch-dashboard
                               │          │          │            │
              ┌────────────────▼┐  ┌──────▼───────┐ │   ┌────────▼──────────┐
              │  3Sixty Admin   │  │  3Sixty       │ │   │ OpenSearch        │
              │  (webapp)       │  │  Discovery    │ │   │ Dashboards        │
              │  :8080          │  │  (webapp)     │ │   │ :5601 (int)       │
              └────────┬────────┘  │  :8080        │ │   │ :15601 (host)     │
                       │           └───────────────┘ │   └────────────────────┘
                       │                             │
              ┌────────▼────────────────────────┐    │
              │  MongoDB  :27017                 │    │
              └─────────────────────────────────┘    │
                                                      │
              ┌───────────────────────────────────────▼──────────────────────────┐
              │  OpenSearch  :9200/:9300                                          │
              └──────────────────────────────────────────────────────────────────┘
                       ▲
                       │
              ┌────────┴────────┐         ┌────────────────────┐
              │  3Sixty RAG     │◄────────►│  Ollama LLM        │
              │  :8888 (int)    │         │  :11434             │
              │  :5000 (host)   │         └────────────────────┘
              └────────┬────────┘
                       │ (gRPC :50052)
              ┌────────▼────────┐
              │  Remote Agent   │
              │  3sixty-RAG     │
              │  :8083          │
              └─────────────────┘

              ┌─────────────────┐         ┌────────────────────┐
              │  RabbitMQ       │◄────────►│  SCIM Server       │
              │  :5672 (int)    │         │  :8083             │
              │  :15672 (mgmt)  │         └────────────────────┘
              └─────────────────┘
```

All services share a single Docker bridge network named `threesixty`. Service discovery is by container name (Docker DNS). In Kubernetes, service discovery is by Kubernetes Service name within the namespace.

---

## 4. Service Catalogue

### 4.1 Core Services (always running)

| Service | Container Name | Image | Internal Port | Host Port | Role |
|---|---|---|---|---|---|
| nginx | nginx-proxy | nginx:1.28.0-alpine | 80, 443 | 80, 443 | Reverse proxy, TLS termination |
| threesixty-admin | threesixty-admin | objective3sixty:5.2.1 | 8080 | — | Admin webapp, REST API |
| threesixty-discovery | threesixty-discovery | objective3sixtydiscovery:5.2.1 | 8080 | — | Discovery / search UI |
| mongo | mongo | mongo:8.0.11 | 27017 | 27017 | Primary database |
| opensearch | opensearch | opensearchproject/opensearch:2.17.1 | 9200, 9300 | 9200, 9300 | Search index, vector store |
| opensearch-dashboard | opensearch-dashboard | opensearchproject/opensearch-dashboards:2.17.1 | 5601 | 15601 | OpenSearch UI |
| rabbitmq | rabbitmq | rabbitmq:4.1-management | 5672, 15672 | 15672 | Message broker (SCIM queue) |
| scim-server | scim-server | objectivescimserver:2.0.0 | 8083 | — | SCIM 2.0 user provisioning |
| ollama | ollama | ollama/ollama:0.17.7 | 11434 | — | Local LLM inference |
| 3sixty-rag | 3sixty-rag | obj3sixtyrag:1.1.2 | 8888 | 5000 | RAG service (hybrid search) |
| remote-agent-3sixty-rag | remote-agent-3sixty-rag | objectiveremoteagentoirag:1.8.0 | 8083 | 8083 | Remote connection agent |
| samba | samba-server | dperson/samba | 445, 139 | 445, 139 | Network share for BFS jobs/exports |

### 4.2 Optional Services

| Service | Compose File | Makefile Target | Notes |
|---|---|---|---|
| Prometheus + Grafana | docker-compose.monitoring.yaml | `monitoring-start/stop` | Metrics and dashboards |
| HashiCorp Vault | docker-compose.vault.yaml | `vault-start/stop` | Dev-mode secrets (dev only) |
| OI Remote Agent | docker-compose.oi-agent.yaml | `oi-agent-start/stop` | Alternate remote agent variant |
| Elasticsearch + Kibana | docker-compose.elasticsearch.yaml | `elasticsearch-start/stop` | **Legacy** — use OpenSearch |

### 4.3 Service Dependencies

```
nginx             → threesixty-admin, threesixty-discovery, scim-server (started)
threesixty-admin  → mongo (healthy)
threesixty-discovery → mongo (healthy), threesixty-admin (started)
scim-server       → mongo (healthy), rabbitmq (healthy)
opensearch-dashboard → opensearch (healthy)
3sixty-rag        → opensearch, ollama (via env config, no compose dependency)
remote-agent-3sixty-rag → threesixty-admin (gRPC, via env config)
```

---

## 5. Technology Choices and Rationale

### 5.1 OpenSearch (not Elasticsearch)

**Decision**: OpenSearch is the preferred and default search engine. Elasticsearch is retained as a legacy optional service only.

**Reasons**:
1. **Licensing**: OpenSearch uses the Apache 2.0 license. Elasticsearch moved to SSPL/Elastic License in 7.11+, which creates compliance concerns for some clients.
2. **AI/Vector capability**: OpenSearch 2.x has native k-NN vector search, neural search, and semantic search plugins that are first-class features. These are required for the RAG/embedding pipeline.
3. **API compatibility**: OpenSearch maintains API compatibility with Elasticsearch 7.x via `compatibility.override_main_response_version`, making migration straightforward.

**Port note**: Both engines use ports 9200 (HTTP) and 9300 (transport). In Docker, only one can bind these host ports simultaneously. OpenSearch owns 9200/9300. If Elasticsearch is run alongside for testing, its host ports are remapped to 19200/19300 in `docker-compose.elasticsearch.yaml`.

In Kubernetes, there is no port conflict — each service gets its own ClusterIP address, and DNS name scopes resolution (`opensearch.namespace.svc:9200` vs `elasticsearch.namespace.svc:9200`).

### 5.2 Ollama (local LLM inference)

Ollama provides local LLM and embedding model inference, eliminating cloud API calls for embedding generation. Models used:
- `mxbai-embed-large` — embedding model for vector search
- `gemma2:2b` — lightweight generative model for query extraction and Q&A

Ollama pulls models on container start. For production, consider baking models into a custom image to avoid pull latency.

### 5.3 Hybrid Search (RAG architecture)

The `3sixty-rag` service implements hybrid search combining:
- **BM25 (text)**: keyword matching via OpenSearch's native text search
- **Vector (semantic)**: k-NN search using Ollama embeddings stored in OpenSearch
- **Reciprocal Rank Fusion**: configurable weights (`RANKER_*` variables) merge both result sets

The LLM provider is configurable via environment variables and supports Objective Foundation API, OpenAI, Google Gemini, or Ollama (local). The provider is selected by uncommenting the relevant block in `.env`.

### 5.4 SCIM + RabbitMQ (user provisioning)

Microsoft Entra ID (Azure AD) pushes user/group changes to the SCIM server over HTTPS. The SCIM server publishes changes to RabbitMQ (`scim-queue`), which 3Sixty Admin consumes asynchronously. This decouples provisioning from the admin service's availability.

### 5.5 Single `.env` file

All services share a single `.env` file rather than per-service env files. This simplifies operations (one file to manage, one `make env-create` step) without meaningful downside — container runtimes pass all variables to all services, and applications ignore variables they don't recognise.

---

## 6. Environment Configuration

### 6.1 Single-file approach

```
.env.sample   →   copy to   →   .env   (gitignored)
```

The `.env.sample` is the canonical reference. It is committed to git and contains `CHANGEME_*` placeholders for all secrets. The `.env` is gitignored and holds actual values.

```bash
# Setup
cp .env.sample .env           # Linux/macOS
copy .env.sample .env          # Windows
# Then edit .env with real values
```

### 6.2 Variable sections and their consumers

| Section | Key Variables | Consumed By |
|---|---|---|
| Global | `TZ`, `GLOBAL_ORG` | All services |
| MongoDB | `MONGO_INITDB_*`, `MONGODB_*` | mongo, threesixty-admin, threesixty-discovery |
| RabbitMQ | `RABBITMQ_*` | rabbitmq, scim-server |
| Azure AD | `CLIENT_ID`, `TENANT_ID`, `CLIENT_SECRET` | threesixty-discovery |
| OpenSearch | `OPENSEARCH_URL`, `OPENSEARCH_USER/PASSWORD` | 3sixty-rag |
| 3Sixty Admin | `SSL_ENABLED`, `APP_URI` | threesixty-admin, threesixty-discovery |
| SCIM | `SCIM_*`, `GRPC_*` | scim-server |
| OI RAG | `OIRAG_*` | oirag (currently commented out in compose) |
| 3sixty RAG | `OPENAI_API_*`, `EMBEDDING_MODEL`, `RANKER_*`, `BEARER_TOKEN` | 3sixty-rag |
| Remote Agent | `REMOTE_AGENT_*`, `TIMEOUT_*`, `SERVER_PORT` | remote-agent-3sixty-rag |
| Vault | `VAULT_*` | vault (optional) |
| Monitoring | `PROMETHEUS_*`, `GRAFANA_*` | monitoring stack (optional) |

### 6.3 LLM Provider selection

The LLM provider is selected in `.env` by keeping one block active and commenting out the others:

```
# Objective Foundation API (default — Objective-hosted, requires API key)
# Google Gemini
# OpenAI
# Ollama (local — no API key, uses ollama container on threesixty network)
```

The active block sets: `OPENAI_API_BASE`, `OPENAI_API_KEY`, `EMBEDDING_MODEL`, `QUESTION_AND_ANSWER_MODEL`, `EXTRACT_SEARCH_QUERY_MODEL`.

### 6.4 Variables requiring action before first start

These must be set before `make start` will work correctly:

| Variable | Section | How to obtain |
|---|---|---|
| `MONGO_INITDB_ROOT_PASSWORD` | MongoDB | Generate: `openssl rand -base64 32` |
| `RABBITMQ_DEFAULT_PASS` | RabbitMQ | Generate: `openssl rand -base64 32` |
| `CLIENT_ID` | Azure AD | Azure Portal → App Registrations |
| `TENANT_ID` | Azure AD | Azure Portal → App Registrations |
| `CLIENT_SECRET` | Azure AD | Azure Portal → App Registrations |
| `OPENAI_API_KEY` | 3sixty RAG | Provider dashboard, or `no-key` for Ollama |
| `REMOTE_AGENT_TOKEN` | Remote Agent | Create agent in Admin UI first |
| `REMOTE_AGENT_NAME` | Remote Agent | Create agent in Admin UI first |
| `BEARER_TOKEN` | 3sixty RAG | Generate any strong random string |

---

## 7. Networking

### 7.1 Docker Compose

All services join a single bridge network named `threesixty`:

```yaml
networks:
  threesixty:
    name: threesixty
    driver: bridge
```

Services discover each other by **container name** (Docker embedded DNS). Example: `3sixty-rag` connects to OpenSearch at `http://opensearch:9200` — Docker resolves `opensearch` to the container's private IP on the bridge.

Port conflicts only occur on **host port bindings** (`host:container`), not on the bridge network where each container has its own IP. This is why OpenSearch and Elasticsearch can both listen on container port 9200 simultaneously without conflict — they only conflict if both try to bind the same host port.

### 7.2 Kubernetes

Services run as `ClusterIP` type — no external exposure except through Ingress. Each service gets its own cluster IP. Service discovery is by Kubernetes DNS: `<service-name>.<namespace>.svc.cluster.local`. The equivalent of container-name resolution in Docker.

There are no port conflicts in Kubernetes even if OpenSearch and Elasticsearch were both enabled — they have different DNS names and different cluster IPs.

### 7.3 External access

| Path | Target |
|---|---|
| `https://localhost/3sixty-admin/` | threesixty-admin:8080 |
| `https://localhost/3sixty-discovery/` | threesixty-discovery:8080 |
| `https://localhost/scim/v2/` | scim-server:8083 |
| `https://localhost/opensearch-dashboard/` | opensearch-dashboard:5601 |
| `https://localhost/kibana/` | kibana:5601 (Elasticsearch only, optional) |
| `http://localhost:15601` | opensearch-dashboard (direct, bypasses nginx) |
| `http://localhost:15672` | RabbitMQ management UI |
| `http://localhost:9200` | OpenSearch API (direct) |
| `http://localhost:19200` | Elasticsearch API (remapped, if running) |
| `http://localhost:5000` | 3sixty-rag API (direct) |
| `http://localhost:8083` | remote-agent-3sixty-rag |

### 7.4 Public URL requirement

SCIM provisioning (Microsoft Entra ID) and the Microsoft Copilot remote agent both require a publicly accessible HTTPS URL. For local development, use a tunnel:

```bash
# Option 1 — ngrok
ngrok http 443

# Option 2 — Cloudflare Tunnel (persistent subdomain)
cloudflared tunnel --url https://localhost
```

---

## 8. Secrets Management

### 8.1 Docker Compose

Secrets are managed via the `.env` file:
- `.env.sample` is committed to git with `CHANGEME_*` placeholders
- `.env` is gitignored (line `.env` in `.gitignore`)
- All `sample.env.*` files are explicitly allowed by `!sample.env.*` in `.gitignore`

**Critical**: API keys, tokens, and passwords must never appear in any `sample.env.*` or `.env.sample` file. All sample files must use `CHANGEME_*` placeholders only.

### 8.2 Kubernetes (Helm)

Credentials are managed exclusively via **external Kubernetes Secrets** created before `helm install`. Helm renders no credentials into its release manifest. Two scripts handle secret creation:

- `helm/kubectl-create-secrets.ps1` — for local Kubernetes / generic clusters
- `helm/aks-create-secrets.ps1` — for Azure AKS (uses Azure CLI)

These scripts must be run once before initial deployment. The secrets they create are referenced by deployments via `secretRef`.

### 8.3 Production recommendations

- Docker: Use HashiCorp Vault in production mode (not dev mode). Mount secrets via Vault Agent or Docker secrets.
- Kubernetes: Use Azure Key Vault with CSI driver, or Sealed Secrets, instead of `kubectl create secret` with plaintext values.

---

## 9. Makefile Automation (Docker Compose)

All Docker Compose operations are accessed via `make` from the `docker-compose/` directory. Run `make help` for a full listing.

### Core operations

| Target | Action |
|---|---|
| `make env-create` | Copy `.env.sample` → `.env` |
| `make certs` | Generate self-signed SSL cert for nginx |
| `make aws-login` | Authenticate Docker to AWS ECR |
| `make start` | Start all core services (`docker compose up -d`) |
| `make stop` | Stop all core services |
| `make restart` | Restart all core services |
| `make clean` | Stop and remove volumes (destructive) |
| `make health` | Show container health status |
| `make logs` | Tail all service logs |
| `make pull` | Pull latest images from ECR |
| `make update` | Pull and restart |

### Optional service operations

| Target | Action |
|---|---|
| `make opensearch-start` | Start OpenSearch + Dashboards independently |
| `make opensearch-stop` | Stop OpenSearch + Dashboards |
| `make elasticsearch-start` | Start legacy Elasticsearch + Kibana (remapped ports) |
| `make monitoring-start/stop` | Prometheus + Grafana |
| `make vault-start/stop` | HashiCorp Vault (dev mode) |
| `make oi-agent-start/stop` | OI Remote Agent (separate compose file) |

### Per-service log targets

`logs-admin`, `logs-discovery`, `logs-mongo`, `logs-nginx`, `logs-opensearch`, `logs-ollama`, `logs-scim`, `logs-rabbitmq`

---

## 10. Helm Chart Reference (Kubernetes)

### 10.1 Structure

```
helm/
  Chart.yaml              # Parent chart: threesixty-stack v1.5.0, appVersion 5.2.1
  values.yaml             # Subchart toggles and global settings
  charts/
    threesixty/           # Admin, Discovery, SCIM, RabbitMQ
    mongo/                # MongoDB
    opensearch/           # OpenSearch + Dashboards
    hybridsearch/         # Ollama, OI-RAG, Remote Agent
    elasticsearch/        # Legacy (disabled by default)
    ingress/              # Traefik ingress routing
```

### 10.2 Enabling/disabling subcharts

```yaml
# helm/values.yaml
elasticsearch:
  enabled: false    # Keep false — use opensearch instead
opensearch:
  enabled: true
hybridsearch:
  enabled: true
```

### 10.3 Deployment

```powershell
# 1. Create secrets (once before first install)
cd helm/
.\aks-create-secrets.ps1        # AKS
# or
.\kubectl-create-secrets.ps1    # Generic K8s

# 2. Install / upgrade
helm dependency update
helm upgrade --install threesixty . -f values.yaml -f values-production.yaml -n threesixty --create-namespace

# 3. Check rollout
kubectl rollout status deployment -n threesixty
```

### 10.4 Port model in Kubernetes

All services are `ClusterIP`. External access is through Traefik ingress. No host port bindings — the port conflict issue that exists in Docker (OpenSearch vs Elasticsearch on 9200) does not exist in Kubernetes.

---

## 11. Version Matrix

| Component | Docker Image Tag | Helm appVersion |
|---|---|---|
| 3Sixty Admin | objective3sixty:5.2.1 | 5.2.1 |
| 3Sixty Discovery | objective3sixtydiscovery:5.2.1 | 5.2.1 |
| SCIM Server | objectivescimserver:2.0.0 | — |
| 3Sixty RAG | obj3sixtyrag:1.1.2 | — |
| Remote Agent (3sixty RAG) | objectiveremoteagentoirag:1.8.0 | — |
| MongoDB | mongo:8.0.11 | — |
| OpenSearch | opensearchproject/opensearch:2.17.1 | — |
| OpenSearch Dashboards | opensearchproject/opensearch-dashboards:2.17.1 | — |
| Ollama | ollama/ollama:0.17.7 | — |
| RabbitMQ | rabbitmq:4.1-management | — |
| Nginx | nginx:1.28.0-alpine | — |
| Helm chart | — | v1.5.0 |

All images are pulled from AWS ECR (`782396859527.dkr.ecr.ap-southeast-2.amazonaws.com`) except public images (nginx, mongo, opensearch, rabbitmq, ollama).

---

## 12. Security Model

### Docker Compose

| Concern | Current State | Production Requirement |
|---|---|---|
| TLS termination | Self-signed cert (nginx) | CA-signed cert (Let's Encrypt or internal CA) |
| OpenSearch auth | `DISABLE_SECURITY_PLUGIN=true` for local dev | Enable security plugin, set strong admin password |
| MongoDB auth | Credentials in `.env` | Rotate regularly, consider Vault |
| CORS | `CORS_ALLOW_ORIGINS=*` in sample | Restrict to specific domain in production |
| Secrets in git | `.env` gitignored; samples use placeholders | Pre-commit hooks to prevent accidental commits |

### Kubernetes

- All services: `ClusterIP` only (no direct external exposure)
- Pod security contexts: `runAsNonRoot`, specific UID/GID, `drop: ["ALL"]` capabilities
- NetworkPolicies: default-deny-ingress baseline + per-flow rules (enable via `networkPolicy.enabled: true`)
- Credentials: external K8s Secrets only, not in Helm manifests

---

## 13. Adapting to a New Container Platform

If the deployment platform changes (e.g., from Docker Compose to Podman/Nomad, or from Helm to Kustomize), the following must be preserved:

### Must-preserve requirements

1. **Single shared network**: All services must be able to reach each other by a stable DNS name. Docker: bridge network `threesixty`. K8s: same namespace, Service names.

2. **Service discovery names**: These names are hardcoded in `.env` defaults and must match the actual container/service name:
   - `mongo` (MongoDB)
   - `opensearch` (OpenSearch API)
   - `opensearch-dashboard` (Dashboards, internal)
   - `threesixty-admin` (Admin webapp, also gRPC target for remote agent)
   - `rabbitmq` (message broker)
   - `ollama` (LLM inference)

3. **Port 9200**: OpenSearch must own this port. If Elasticsearch is also deployed, remap its host-accessible port to avoid binding conflict.

4. **Port 5601**: OpenSearch Dashboards internal. If exposed on the host, use `15601` to avoid potential Kibana conflict.

5. **Environment variables**: All variables in `.env.sample` must be passed to the appropriate services. In a new platform, map sections to services as documented in §6.2.

6. **Startup ordering**: Services have readiness dependencies — MongoDB must be healthy before Admin and Discovery start. OpenSearch must be healthy before Dashboards starts. See §4.3.

7. **Persistent volumes**: MongoDB (`mongo_data`), OpenSearch (`opensearch_data`), and Ollama (`ollama_data`) require persistent storage. Data loss on container restart is not acceptable.

8. **Nginx / reverse proxy**: The path routing table in §7.3 must be preserved. The proxy must forward `Host`, `X-Forwarded-For`, `X-Forwarded-Proto` headers.

9. **TLS**: nginx (or the replacement proxy) must terminate TLS. Internal service-to-service communication is plaintext within the trusted network.

10. **Resource minimums**: OpenSearch requires at least 3GB RAM and `vm.max_map_count >= 262144` on the host. Ollama requires 4–8GB depending on loaded models.

---

## 14. Known Issues and Workarounds

| Issue | Workaround |
|---|---|
| Ollama pulls models on every container start | Models are stored in the `ollama_data` volume — they persist across restarts, only pulled if missing |
| OpenSearch healthcheck uses `admin:admin` credentials | When security plugin is enabled, update healthcheck credentials in compose file |
| `vm.max_map_count` too low for OpenSearch | Run `sysctl -w vm.max_map_count=262144` on host; in K8s, use a DaemonSet init container |
| `REMOTE_AGENT_NAME` vs `REMOTE_AGENT_AGENT_NAME` | Both are set in `.env` to the same value; verify which the container image actually reads |
| Windows line endings in shell scripts | `init-mongo.sh` must use LF, not CRLF; see README for VS Code fix |
| SCIM requires public URL | Use ngrok or Cloudflare Tunnel for local development |

---

*This document should be updated whenever a service version changes, a new service is added, or an architectural decision is revised.*
