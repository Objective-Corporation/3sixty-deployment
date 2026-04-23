# 3Sixty Kubernetes Deployment

Helm charts for deploying the complete 3Sixty application stack to Kubernetes (AKS).

---

## Quick Links

- [Quick Start Guide](QUICK-START.md) — step-by-step deployment instructions
- [Secrets Management](SECRETS-MANAGEMENT.md) — credential setup and rotation
- [Makefile reference](#makefile-reference) — automation targets

---

## Architecture

The 3Sixty stack is a parent Helm chart with six subcharts:

| Subchart          | Component(s)                                          | Version |
| ----------------- | ----------------------------------------------------- | ------- |
| `threesixty`      | Admin webapp, Discovery webapp, SCIM server, RabbitMQ | 5.2.0   |
| `mongo`           | MongoDB database                                      | 8.0.11  |
| `opensearch`      | OpenSearch search engine + Dashboards UI              | 2.4.1   |
| `hybridsearch`    | Ollama LLM server, OI-RAG service, Remote Agent       | —       |
| `elasticsearch`   | Legacy single-node Elasticsearch (optional)           | 7.17.0  |
| `traefik`         | Traefik ingress controller (bundled)                  | 39.0.5  |

Each subchart can be independently enabled or disabled in `values.yaml` / `values-production.yaml`.

---

## Prerequisites

| Tool           | Minimum version | Purpose                                       |
| -------------- | --------------- | --------------------------------------------- |
| Kubernetes     | 1.24            | Target cluster                                |
| Helm           | 3.12            | Chart packaging and lifecycle management      |
| kubectl        | 1.28            | Cluster access                                |
| AWS CLI        | 2.0             | ECR registry authentication (image pull)      |
| Azure CLI      | 2.50            | AKS credential retrieval (AKS deployments)    |
| OpenSSL        | 3.0             | Self-signed TLS certificate generation        |
| PowerShell     | 7.0             | Secrets setup scripts (`pwsh`)                |

Check all tools are installed (Linux / macOS / Windows):

```bash
make check-prerequisites
```

This prints install instructions for any missing tools on your platform.

---

## Secrets Management

All sensitive credentials are stored in Kubernetes Secrets that are **created before Helm runs** — they are never embedded in values files or committed to Git.

Two scripts handle secret creation depending on your cluster access model:

| Script                       | Use when                                             | Platform        |
| ---------------------------- | ---------------------------------------------------- | --------------- |
| `kubectl-create-secrets.sh`  | You have direct `kubectl` access (local kubeconfig)  | Linux/macOS/Win |
| `aks-create-secrets.sh`      | You use `az aks command invoke` (AKS API access)     | Linux/macOS/Win |

See [SECRETS-MANAGEMENT.md](SECRETS-MANAGEMENT.md) for the complete guide.

### Secrets created by setup scripts

- `ecr-registry-secret` — AWS ECR image pull credentials
- `traefik-tls` — TLS certificate and private key
- `{release}-rabbitmq-secret` — RabbitMQ credentials
- `{release}-mongo-init-secret` — MongoDB root credentials
- `{release}-opensearch-admin-secret` — OpenSearch admin password
- `{release}-hybridsearch-oirag-secret` — OI-RAG service credentials
- `{release}-hybridsearch-remoteagent-secret` — Remote Agent credentials

### Secrets managed by Helm (from values-production.yaml)

- OAuth2 / OIDC credentials for Discovery and Admin
- SCIM server credentials
- MongoDB connection strings

---

## Configuration Hierarchy

Understanding which file is authoritative for each setting prevents drift between the secrets scripts, Helm values, and the deployed chart.

```text
values-production.yaml         ← AUTHORITATIVE: all deployment config overrides
Chart.yaml (appVersion)        ← INFORMATIONAL: tracks the app version (not used by templates)
kubectl-create-secrets.sh      ← AUTHORITATIVE: all credential values + derived URIs
  │
  ├── NAMESPACE        must match Makefile NAMESPACE (default: threesixty)
  ├── RELEASE_NAME     must match Makefile RELEASE   (default: threesixty-stack)
  └── RELEASE_NAME-mongo  →  MONGO_HOST used in MongoDB URI
                              must match values-production.yaml env.admin.RABBITMQ_HOST prefix
```

### Key invariants

| Setting | Defined in | Read by |
| ------- | ---------- | ------- |
| `NAMESPACE` | Makefile `NAMESPACE ?=` | All `kubectl` and `helm` targets; secrets scripts |
| `RELEASE` / `RELEASE_NAME` | Makefile `RELEASE ?=` and top of secrets script | Helm release name; Kubernetes secret names; service DNS names |
| `image.tag` | `charts/threesixty/values.yaml` (default) or `values-production.yaml` | Deployment templates — **not** read from `Chart.yaml appVersion` |
| `ingress.host` / `ingress.tls.hosts` | `values-production.yaml` | `charts/ingress/templates/ingress.yaml` — defaults in subchart `values.yaml` are placeholders only |
| Credentials | Top of `kubectl-create-secrets.sh` (or `aks-create-secrets.sh`) | Never in Helm values. Stored only in Kubernetes Secrets. |

### Changing the release name or namespace

If you change `RELEASE` or `NAMESPACE` from their defaults, update **all three places** consistently:

| File | Setting |
| ---- | ------- |
| Makefile | `RELEASE ?= threesixty-stack` and `NAMESPACE ?= threesixty` |
| `kubectl-create-secrets.sh` | `RELEASE_NAME=` and `NAMESPACE=` near the top |
| `aks-create-secrets.sh` | `RELEASE_NAME=` and `--namespace` argument default |
| `values-production.yaml` | `env.admin.RABBITMQ_HOST: "<release>-rabbitmq"` |

### Platform support

All tooling (Makefile, secrets scripts) runs natively on **Linux, macOS, and Windows (Git Bash)**. No PowerShell is required.

The Helm charts and values files are entirely platform-agnostic — they are pure YAML interpreted by Helm.

---

## Configuration

### Enable/Disable Subcharts

In `values.yaml` (default) or `values-production.yaml`:

```yaml
mongo:
  enabled: true

threesixty:
  enabled: true

opensearch:
  enabled: true

hybridsearch:
  enabled: true

elasticsearch:
  enabled: false   # Legacy — disable unless required

traefik:
  enabled: true
```

### Production Configuration

1. Copy the template: `cp values-production.yaml.template values-production.yaml`
2. Fill in all required values (see comments in the template)
3. Do not commit `values-production.yaml` — it is in `.gitignore`

Required values include:

- ECR image registry URL and tag (`threesixty.image.registry`, `.tag`)
- Azure AD / Entra ID OAuth2 credentials (`threesixty.oauth2.*`)
- RabbitMQ credentials — **must match** values in the setup script
- MongoDB connection details
- Domain name (`ingress.domain`)

---

## Deployment Workflow

```text
1. Setup tools          →  make setup-kubectl
2. Check cluster        →  kubectl config get-contexts
                           kubectl config use-context <context-name>
                           kubectl cluster-info   (or make aks-credentials)
3. Create secrets       →  make secrets-kubectl  (or make secrets-aks)
                           (also creates the namespace if it does not exist)
4. Verify secrets       →  make verify-secrets
5. Configure values     →  edit values-production.yaml
6. Fetch dependencies   →  make deps
7. Install              →  make install
8. Verify               →  make status
```

### Cluster context commands

```powershell
# Show the active cluster context
kubectl config current-context

# List all contexts (active context marked with *)
kubectl config get-contexts

# Switch to a different cluster
kubectl config use-context <context-name>

# For AKS: fetch credentials and set context in one step
make aks-credentials AKS_RG=<resource-group> AKS_CLUSTER=<cluster-name>
```

### Namespace

The default namespace is `threesixty`. It is created automatically by the secrets setup scripts. If you use a different namespace, update it consistently in all three places:

| Location | Setting |
| -------- | ------- |
| `kubectl-create-secrets.ps1` | `$NAMESPACE = "threesixty"` |
| `aks-create-secrets.ps1` | `-Namespace` parameter (default `"threesixty"`) |
| Makefile | `NAMESPACE ?= threesixty` (or `make install NAMESPACE=<ns>`) |

`values-production.yaml` has no namespace setting — it is passed to Helm via `--namespace` from the Makefile.

For upgrades (config changes, image updates):

```text
1. Edit values-production.yaml
2. make upgrade
```

---

## Makefile Reference

Run `make help` for the full list. Key targets:

| Target                    | Description                                                      |
| ------------------------- | ---------------------------------------------------------------- |
| `make help`               | Show all targets with descriptions                               |
| `make check-prerequisites`| Check kubectl, helm, aws, az, openssl, jq are installed          |
| `make aks-credentials`    | Configure kubectl for AKS cluster                                |
| `make secrets-kubectl`    | Run kubectl secrets setup script                                 |
| `make secrets-aks`        | Run AKS invoke secrets setup script                              |
| `make verify-secrets`     | Check all required secrets exist in the namespace                |
| `make deps`               | Download Helm subchart dependencies                              |
| `make install`            | Install the Helm release (first deployment)                      |
| `make upgrade`            | Upgrade the Helm release (subsequent deployments)                |
| `make status`             | Show release status and pod states                               |
| `make pods`               | Watch pod status in real time                                    |
| `make logs`               | Tail logs: `make logs DEPLOY=admin`                              |
| `make events`             | Show recent Kubernetes events                                    |
| `make rollback`           | Roll back to the previous release revision                       |
| `make lint`               | Lint Helm templates                                              |
| `make template`           | Render templates locally (dry run)                               |
| `make validate`           | Lint + render (full dry-run validation)                          |
| `make install-metallb`    | Install MetalLB + apply `metallb-config.yaml` (bare-metal only)  |
| `make uninstall`          | Remove the Helm release (PVCs retained)                          |
| `make purge`              | Remove release AND all PVCs (all data deleted)                   |

### Custom release name or namespace

```powershell
make install RELEASE=my-release NAMESPACE=my-ns VALUES_FILE=my-values.yaml
```

---

## Resource Requirements

Approximate resource requirements for a full production deployment:

| Component        | Memory request | Memory limit | CPU request | CPU limit |
| ---------------- | -------------- | ------------ | ----------- | --------- |
| Admin            | 512Mi          | 2Gi          | 500m        | 2000m     |
| Discovery        | 512Mi          | 2Gi          | 500m        | 2000m     |
| SCIM Server      | 256Mi          | 1Gi          | 250m        | 1000m     |
| RabbitMQ         | 256Mi          | 512Mi        | 100m        | 500m      |
| MongoDB          | 512Mi          | 2Gi          | 250m        | 1000m     |
| OpenSearch       | 3Gi            | 5Gi          | 500m        | 2000m     |
| OI-RAG           | 512Mi          | 2Gi          | 250m        | 1000m     |
| Remote Agent     | 256Mi          | 1Gi          | 250m        | 1000m     |
| Ollama (LLM)     | 4Gi            | 16Gi         | 1000m       | 4000m     |

**Minimum cluster size**: 3 nodes × 8 vCPU / 32 GB RAM (without GPU).
Ollama can run on CPU but is significantly slower than GPU.

**OpenSearch note**: OpenSearch requires `vm.max_map_count ≥ 262144` on each cluster node.
Set via a privileged init DaemonSet or node configuration:
`sysctl -w vm.max_map_count=262144`

---

## Persistent Data

PVCs are annotated with `helm.sh/resource-policy: keep` — they survive `helm uninstall`.
This protects MongoDB, OpenSearch, Elasticsearch, and Ollama model data.

To fully wipe all data: `make purge` (irreversible).

---

## Security

All pods run as non-root with `allowPrivilegeEscalation: false` and `capabilities.drop: ALL`.

| Component    | UID  | Notes                                                                                              |
| ------------ | ---- | -------------------------------------------------------------------------------------------------- |
| Admin        | 1000 | Runs as container default user (root required for startup chmod/gosu — see security backlog H-02a) |
| Discovery    | 1000 | Runs as container default user (root required for startup chmod/gosu — see security backlog H-02a) |
| SCIM         | 1000 | Runs as container default user (root required for startup chmod/gosu — see security backlog H-02a) |
| MongoDB      | 999  | Official MongoDB image default                                                                     |
| RabbitMQ     | 999  | Official RabbitMQ image default                                                                    |
| OpenSearch   | 1000 | Official OpenSearch image default                                                                  |
| OI-RAG       | 1000 | OI-RAG service user                                                                                |
| Remote Agent | 1000 | Remote Agent service user                                                                          |
| Ollama       | 0    | Ollama official image requires root                                                                |

---

## Versioning and Upgrades

Each subchart has an independent version in its `Chart.yaml`. The parent chart version in `Chart.yaml` should be incremented when templates or values change.

```bash
# Check current Helm release history
make history

# Roll back to a specific revision
helm rollback threesixty-stack <revision> --namespace threesixty
```

See `Chart.yaml` for the full versioning guide.

---

## Troubleshooting

```powershell
# Check pod status and events
make status
make events

# Inspect logs for a failing pod
make logs DEPLOY=admin

# Decode a secret value
kubectl get secret threesixty-stack-rabbitmq-secret -n threesixty \
    -o jsonpath='{.data.RABBITMQ_DEFAULT_USER}' | base64 -d

# Check PVC binding
kubectl get pvc -n threesixty

# Force-restart a deployment
kubectl rollout restart deployment/threesixty-stack-threesixty-admin -n threesixty
```

Common issues:

- **ImagePullBackOff**: ECR token expired (valid 12h) — re-run secrets script
- **OpenSearch CrashLoopBackOff**: `vm.max_map_count` too low on node
- **Ollama slow start**: Normal — model pull takes up to 10 minutes on cold start
- **Admin/SCIM can't connect to RabbitMQ**: RabbitMQ password mismatch between secret and `values-production.yaml`
- **Remote Agent CrashLoopBackOff**: Requires a real REMOTE_AGENT_TOKEN registered in the admin UI. Set `hybridsearch.remoteagent.enabled: false` until token is available.
