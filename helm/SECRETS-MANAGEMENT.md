# Secrets Management Guide

This guide explains how credentials are managed for 3Sixty Kubernetes deployments.

---

## Security Model

All sensitive credentials are stored in **Kubernetes Secrets that are created out-of-band** — before Helm is run. They are never embedded in Helm values files or committed to Git.

The Helm chart references these secrets by name via `secretRef` and `secretKeyRef` in the deployment templates. Helm does **not** create or modify these secrets during `helm install` / `helm upgrade`.

---

## Two Approaches

The default approach is **`kubectl-create-secrets.ps1`**. Use the AKS script only if you cannot access the cluster directly via `kubectl`.

| Script | When to use | Default? |
| --- | --- | --- |
| `kubectl-create-secrets.ps1` | Direct `kubectl` access to the cluster (local kubeconfig configured) | **Yes** |
| `aks-create-secrets.ps1` | No direct cluster access; connects via `az aks command invoke` through Azure | No |

Both scripts create the same set of secrets with the same names and keys.

---

## Required Secrets

The following secrets must exist in the `threesixty` namespace before `helm install`:

| Secret Name | Contains | Created by |
| --- | --- | --- |
| `ecr-registry-secret` | AWS ECR pull credentials | Setup scripts |
| `traefik-tls` | TLS certificate + private key | Setup scripts |
| `{release}-rabbitmq-secret` | RabbitMQ username + password | Setup scripts |
| `{release}-mongo-init-secret` | MongoDB root username + password | Setup scripts |
| `{release}-opensearch-admin-secret` | OpenSearch admin password | Setup scripts |
| `{release}-hybridsearch-oirag-secret` | OpenSearch password + OI-RAG bearer token | Setup scripts |
| `{release}-hybridsearch-remoteagent-secret` | Remote agent token + SSL CA password | Setup scripts |
| `{release}-oauth2-secret` | Azure AD client ID, tenant ID, client secret, scopes | Setup scripts |
| `{release}-admin-secret` | MongoDB URI, RabbitMQ credentials, SCIM credentials | Setup scripts |
| `{release}-scim-secret` | SCIM credentials, SCIM MongoDB connection string | Setup scripts |

Where `{release}` is the Helm release name (default: `threesixty-stack`).

There are also Helm-managed secrets for SCIM and MongoDB connection credentials. These are created by Helm from `values-production.yaml` during install. See the [Helm-Managed Secrets](#helm-managed-secrets) section below.

---

## Credential Variables

Both setup scripts require the following credentials to be filled in at the top of the script before running:

```powershell
$RELEASE_NAME           = "threesixty-stack"   # Must match your helm install release name
$NAMESPACE              = "threesixty"

$MONGO_ROOT_USERNAME    = ""   # MongoDB root username (e.g. "threesixty-db-admin")
$MONGO_ROOT_PASSWORD    = ""   # MongoDB root password (strong random — no $ or ' chars)

$RABBITMQ_USER          = ""   # RabbitMQ username (e.g. "rabbitmq-admin")
$RABBITMQ_PASS          = ""   # RabbitMQ password
                               # IMPORTANT: This value must also be set in values-production.yaml
                               # under threesixty.rabbitmq.username / .password

$OPENSEARCH_PASSWORD    = ""   # OpenSearch admin password
                               # Used by both OpenSearch pod and OI-RAG service
                               # Username is always 'admin'

$OIRAG_BEARER_TOKEN     = ""   # OI-RAG API bearer token

$REMOTE_AGENT_TOKEN     = ""   # Remote agent authentication token
$SSL_CA_PASSWORD        = ""   # SSL CA keystore password for remote agent

$SCIM_USERNAME          = ""   # SCIM server username (e.g. "scim-application-admin")
$SCIM_PASSWORD          = ""   # SCIM server password

# MongoDB connection details — used to build connection URIs (host derived from release name)
$MONGO_DATABASE         = "simflofy"       # Change only if using a custom database name
$MONGO_SCIM_DATABASE    = "scim-database"  # Change only if using a custom SCIM database name

# OAuth2 / Azure AD credentials (get these from Azure Portal > App Registrations)
$OAUTH2_CLIENT_ID       = ""   # Application (client) ID
$OAUTH2_TENANT_ID       = ""   # Directory (tenant) ID
$OAUTH2_CLIENT_SECRET   = ""   # Client secret value (from Certificates & Secrets tab)
$OAUTH2_SCOPES          = "openid,profile,email,offline_access"   # Default — adjust if needed
```

**Password rules**: Avoid `$`, `'`, `"`, and backticks in passwords. These characters cause escaping issues in shell commands transmitted via the AKS API.

---

## Step-by-Step: kubectl Approach

### kubectl Prerequisites

- `kubectl` configured with cluster access (`kubectl cluster-info` succeeds)
- AWS CLI authenticated (`aws sts get-caller-identity` succeeds)
- OpenSSL installed

### kubectl Steps

```powershell
# 1. Open and fill in credentials at the top of the script
code kubectl-create-secrets.ps1

# 2. Run the script
pwsh -File kubectl-create-secrets.ps1

# 3. Verify all secrets were created
make verify-secrets
```

---

## Step-by-Step: AKS Invoke Approach

### AKS Prerequisites

- Azure CLI installed and authenticated (`az login`)
- AKS cluster name and resource group
- AWS CLI authenticated (`aws sts get-caller-identity` succeeds)

### AKS Steps

```powershell
# 1. Open and fill in credentials at the top of the script
code aks-create-secrets.ps1

# 2. Run the script
pwsh -File aks-create-secrets.ps1

# 3. Verify all secrets were created
make verify-secrets
```

### How AKS Invoke Works

The `aks-create-secrets.ps1` script uses `az aks command invoke` to execute `kubectl` commands inside the cluster. To handle special characters safely, it:

1. Builds Kubernetes Secret YAML locally in PowerShell
2. Base64-encodes the entire YAML manifest
3. Transmits it as: `echo <base64> | base64 -d | kubectl apply -f -`

This avoids shell escaping issues when passwords are transmitted through the AKS API.

---

## Helm-Managed Secrets

All credentials are now managed externally via setup scripts (C-02 remediation complete). There are no longer any Helm-rendered secrets containing credentials — the Helm release manifest stored in etcd contains no sensitive values.

The four `secret-*.yaml` template files (`secret-admin.yaml`, `secret-scim.yaml`, `secret-mongodb.yaml`, `secret-discovery.yaml`) are stub comment files retained for reference only. No Secret objects are created from them.

---

## OpenSearch Admin Credentials

The OpenSearch `admin` user password is stored in `{release}-opensearch-admin-secret`.

- **Username**: `admin` (always — this is the built-in OpenSearch superuser)
- **Password**: The value of `$OPENSEARCH_PASSWORD` you set in the setup script

**Important**: This password is shared between:

1. The `OPENSEARCH_INITIAL_ADMIN_PASSWORD` env var in the OpenSearch pod
2. The `OPENSEARCH_PASSWORD` env var in the OI-RAG pod

Both must match for the RAG service to connect to OpenSearch.

---

## RabbitMQ Credentials in values-production.yaml

RabbitMQ credentials appear in two places:

1. **Kubernetes Secret** (`{release}-rabbitmq-secret`) — created by setup scripts — used by the RabbitMQ pod itself
2. **values-production.yaml** (`threesixty.rabbitmq.username` / `.password`) — used by the admin and SCIM services to connect to RabbitMQ

These **must match**. If they differ, the admin and SCIM services will fail to connect.

---

## Rotating Credentials

To rotate a credential:

```powershell
# Update the Kubernetes secret
kubectl create secret generic threesixty-stack-rabbitmq-secret `
    --from-literal=RABBITMQ_DEFAULT_USER=<user> `
    --from-literal=RABBITMQ_DEFAULT_PASS=<new-password> `
    --namespace threesixty `
    --dry-run=client -o yaml | kubectl apply -f -

# Restart the affected pods to pick up the new secret
kubectl rollout restart deployment/threesixty-stack-threesixty-rabbitmq -n threesixty
kubectl rollout restart deployment/threesixty-stack-threesixty-admin -n threesixty
kubectl rollout restart deployment/threesixty-stack-threesixty-scim-server -n threesixty
```

---

## Verifying Secrets

```bash
# List all secrets
make verify-secrets

# Inspect a specific secret (base64-encoded)
kubectl get secret threesixty-stack-rabbitmq-secret -n threesixty -o yaml

# Decode a specific key
kubectl get secret threesixty-stack-rabbitmq-secret -n threesixty \
    -o jsonpath='{.data.RABBITMQ_DEFAULT_USER}' | base64 -d
```

---

## Security Notes

- `values-production.yaml` is listed in `.gitignore` — do not commit it.
- Setup scripts contain credentials in plaintext — do not commit them after filling in credentials.
- PVCs are annotated with `helm.sh/resource-policy: keep` — they are not deleted when the Helm release is uninstalled. Run `make purge` to intentionally delete all data.
