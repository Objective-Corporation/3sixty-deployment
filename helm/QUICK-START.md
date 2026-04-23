# 3Sixty Production Deployment — Quick Start

This guide covers the fastest path to a running 3Sixty stack on Kubernetes (AKS).
Full details are in [README.md](README.md) and [SECRETS-MANAGEMENT.md](SECRETS-MANAGEMENT.md).

---

## Prerequisites

Required tools (Linux, macOS, Windows — all platforms):

- [kubectl](https://kubernetes.io/docs/tasks/tools/) ≥ 1.28
- [Helm](https://helm.sh/docs/intro/install/) ≥ 3.12
- [AWS CLI](https://aws.amazon.com/cli/) ≥ 2 (for ECR image pull credentials)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) ≥ 2.50 (for AKS deployments)
- [OpenSSL](https://www.openssl.org/) (for TLS certificate generation)
- [jq](https://jqlang.github.io/jq/) (for `aks-create-secrets.sh` JSON parsing)

Check all tools in one step:

```bash
make check-prerequisites
```

This prints install instructions for any missing tool on your platform (macOS `brew`, Ubuntu `apt`, Windows `winget`).

> **Windows:** The Makefile and `.sh` scripts run through **Git Bash** (included with Git for Windows). No PowerShell is required.

---

## Step 1 — Connect to the Cluster

### Check your current cluster context

Before doing anything, confirm you are pointed at the right cluster:

```bash
# Show the active context (cluster + user + namespace)
kubectl config current-context

# List all available contexts and highlight the active one
kubectl config get-contexts
```

### Switch to a different cluster

```bash
# Switch to a named context from your kubeconfig
kubectl config use-context <context-name>
```

### Direct kubectl access (local kubeconfig)

```bash
# Verify cluster connectivity after switching context
kubectl cluster-info
```

### AKS without direct network access

```bash
# Fetches AKS credentials and sets the active context automatically
make aks-credentials AKS_RG=<resource-group> AKS_CLUSTER=<cluster-name>
```

---

## Step 2 — Create Kubernetes Secrets

All credentials are stored in Kubernetes Secrets created **before** Helm runs.

### Namespace

The secrets scripts **automatically create the namespace** if it does not exist. The default namespace is `threesixty`.

If you need a different namespace, update it in **all three places** before running anything:

| File | Setting |
| ---- | ------- |
| `kubectl-create-secrets.sh` | `NAMESPACE=` near the top of the file |
| `aks-create-secrets.sh` | `NAMESPACE=` near the top of the file |
| Makefile / `make` commands | `NAMESPACE ?= threesixty` — or pass `NAMESPACE=<ns>` to every `make` call |

`values-production.yaml` does not contain a namespace setting — Helm reads it from the `--namespace` flag, which the Makefile supplies via the `NAMESPACE` variable.

### Option A — Direct kubectl access

1. Copy the example script and fill in your credentials:

   ```bash
   cp kubectl-create-secrets.sh.example kubectl-create-secrets.sh
   # edit kubectl-create-secrets.sh — set all variables at the top
   ```

2. Run:

   ```bash
   make secrets-kubectl
   ```

   > The first `make secrets-kubectl` will copy the example automatically if you haven't done step 1 yet, then exit asking you to set credentials.

### Option B — AKS invoke (no direct kubectl access)

1. Copy the example script and fill in your credentials:

   ```bash
   cp aks-create-secrets.sh.example aks-create-secrets.sh
   # edit aks-create-secrets.sh — set all variables at the top
   ```

2. Run:

   ```bash
   make secrets-aks AKS_RG=<resource-group> AKS_CLUSTER=<cluster-name>
   ```

### Verify secrets were created

```bash
make verify-secrets
```

All 7 secrets should show `[OK]`. See [SECRETS-MANAGEMENT.md](SECRETS-MANAGEMENT.md) for the full list.

---

## Step 3 — Configure values-production.yaml

```bash
# Copy the template
cp values-production.yaml.template values-production.yaml

# Edit with your values
code values-production.yaml   # or any editor
```

Required values to fill in:

| Section | Required fields |
| ------- | --------------- |
| `traefik` | `ingressClassName: threesixty-stack-traefik` (set automatically). Ports: `exposedPort.http: 7070`, `exposedPort.https: 7443` (change for AKS/EKS LoadBalancer deployments). |
| `threesixty.rabbitmq` | `username`, `password` — **must match** `$RABBITMQ_USER`/`$RABBITMQ_PASS` in setup script |
| `threesixty.oauth2` | `clientId`, `tenantId`, `clientSecret` — from Azure AD App Registration |
| `threesixty.env.admin` | `MONGO_USERNAME`, `MONGO_PASSWORD`, `MONGO_HOST` |
| `hybridsearch.oirag` | `OPENSEARCH_USER` — always `admin` |
| `hybridsearch.remoteagent.enabled` | `false` until a real token is created in the admin UI |

**Do not** commit `values-production.yaml` — it is in `.gitignore`.

---

## Step 4 — Install

```bash
# Download subchart dependencies (only needed once, or after Chart.yaml changes)
make deps

# Install the Helm release
make install
```

This runs `helm install` with `--wait --timeout 10m`. Pods that take longer to start
(Ollama model pull, OpenSearch JVM startup) are covered by startup probes.

---

## Step 5 — Verify

```bash
# Check all pods are Running/Ready
make status

# Watch pods in real time
make pods

# Check logs for a specific component
make logs DEPLOY=admin
make logs DEPLOY=oi-rag
make logs DEPLOY=search
```

---

## Accessing the Application

Once all pods are running, access the 3Sixty admin UI via Traefik:

### Add domain to hosts file (local/Docker Desktop deployments)

**Linux / macOS:**

```bash
echo "127.0.0.1 threesixty.objective.com" | sudo tee -a /etc/hosts
```

**Windows (Git Bash as Administrator):**

```bash
echo "127.0.0.1 threesixty.objective.com" >> /c/Windows/System32/drivers/etc/hosts
```

### Connect to the admin UI

- **Local/Docker Desktop**: `https://threesixty.objective.com:7443/3sixty-admin` (port 7443)
- **AKS/EKS with LoadBalancer**: `https://threesixty.objective.com/3sixty-admin` (port 443)

The browser will warn about the self-signed certificate (if used) — click **Advanced** → **Proceed** to continue.

**Default credentials**: Use the OAuth2 user configured in your Azure AD App Registration.

---

## MetalLB (bare-metal / on-premises clusters only)

MetalLB provides `LoadBalancer` service support on clusters that don't have a cloud provider
load balancer (bare-metal, on-premises, kubeadm, k3s, etc.).

> **Do NOT install MetalLB on AKS, EKS, or GKE** — those platforms provide native load balancing.

### Step 1 — Configure your IP range

Edit [metallb-config.yaml](metallb-config.yaml) and set the IP address range to a block that is:

- On the same subnet as your Kubernetes nodes
- Not assigned by DHCP or other devices
- Reachable by clients that need to access services

```yaml
# Example for a 192.168.1.x network:
addresses:
  - 192.168.1.100-192.168.1.110
```

### Step 2 — Install MetalLB

```bash
make install-metallb
```

This single target:

1. Adds the MetalLB Helm repository
2. Installs MetalLB into the `metallb-system` namespace
3. Waits for the MetalLB controller to be ready
4. Applies `metallb-config.yaml` (IP pool + L2 advertisement)

---

## Common Operations

| Task | Command |
| ---- | ------- |
| Deploy config change | `make upgrade` |
| Check pod logs | `make logs DEPLOY=<component>` |
| View Kubernetes events | `make events` |
| Roll back to previous version | `make rollback` |
| View release history | `make history` |
| Dry-run / validate templates | `make validate` |
| Uninstall (keep data) | `make uninstall` |
| Uninstall + delete all data | `make purge` |

Run `make help` for the full list of targets and configuration variables.

---

## Azure AD / Entra ID App Registration

The 3Sixty Discovery service uses OAuth2/OIDC for user authentication. You need an App Registration in your Azure AD tenant.

1. In the Azure Portal, go to **Azure Active Directory → App registrations → New registration**
2. Set the Redirect URI to: `https://<your-domain>/3sixty-discovery/login/oauth2/code/azure`
3. Under **Certificates & secrets**, create a new client secret
4. Copy the **Application (client) ID**, **Directory (tenant) ID**, and the client secret value into `values-production.yaml`

---

## TLS Certificate

### Self-signed certificate (development)

The secrets scripts (`kubectl-create-secrets.sh` / `aks-create-secrets.sh`) generate a self-signed certificate automatically using `openssl` and create the `traefik-tls` Kubernetes secret. No manual steps are needed if you run the setup script first.

To generate and apply a self-signed certificate manually (Linux, macOS, Windows Git Bash):

```bash
mkdir -p certs
openssl req -x509 -newkey rsa:2048 -days 365 \
    -nodes \
    -keyout certs/tls.key \
    -out  certs/tls.crt \
    -subj "/CN=threesixty.objective.com"

kubectl create secret tls traefik-tls \
    --cert=certs/tls.crt \
    --key=certs/tls.key \
    -n threesixty
```

### Using a CA-signed certificate (production)

```bash
kubectl create secret tls traefik-tls \
    --cert=/path/to/cert.crt \
    --key=/path/to/cert.key \
    --namespace threesixty \
    --dry-run=client -o yaml | kubectl apply -f -
```

---

## Troubleshooting

**Pod stuck in `Pending`**
Check storage class and PVC binding: `kubectl get pvc -n threesixty`

**Pod stuck in `Init:0/1` or `CrashLoopBackOff`**
Check events and logs: `make events` then `make logs DEPLOY=<name>`

**ECR pull fails (`ImagePullBackOff`)**
The ECR token expires after 12 hours. Re-run the secrets script to refresh it.

**OpenSearch fails to start**
The cluster node needs `vm.max_map_count ≥ 262144`. Set it via a DaemonSet or:
`kubectl exec -n threesixty <node-pod> -- sysctl -w vm.max_map_count=262144`

**Ollama startup takes > 5 minutes**
This is expected on the first start — Ollama pulls the LLM model (~4 GB). The startup probe allows up to 10 minutes. The model is cached in the PVC for subsequent restarts.
