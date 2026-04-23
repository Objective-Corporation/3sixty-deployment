# Security Guide — 3Sixty Helm Deployment

This document covers the security model implemented in the 3Sixty Helm charts and
provides operational instructions for HTTPS, TLS certificates, and credential management.

---

## Secrets Management

All credentials are created **out-of-band** by PowerShell setup scripts before
`helm install` is run. Helm never renders credentials into its release manifest.
See [SECRETS-MANAGEMENT.md](SECRETS-MANAGEMENT.md) for the full list of required
secrets and step-by-step setup instructions.

**What this means in practice:**

- `helm get values` and the Helm release object in etcd contain no credentials
- `values-production.yaml` contains no passwords — only non-sensitive configuration
- Credential rotation is done by updating the Kubernetes Secret directly and
  restarting the affected pods (see [SECRETS-MANAGEMENT.md](SECRETS-MANAGEMENT.md))

---

## HTTPS and TLS Configuration

### Enforcing HTTPS Redirect (L-04)

By default the ingress defines TLS but does not redirect plain HTTP to HTTPS.
Users accessing via `http://` would transmit credentials in plaintext.

**Fix — add a Traefik redirect middleware:**

1. Create the middleware in the `traefik` namespace (or wherever Traefik is deployed):

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: redirect-to-https
  namespace: traefik
spec:
  redirectScheme:
    scheme: https
    permanent: true
```

Apply it:

```bash
kubectl apply -f redirect-middleware.yaml
```

1. Reference it in `values-production.yaml` by adding an annotation to the ingress:

```yaml
ingress:
  enabled: true
  ingressClassName: traefik
  host: your-domain.com
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: "traefik-redirect-to-https@kubernetescrd"
  tls:
    - secretName: traefik-tls
      hosts:
        - your-domain.com
```

The annotation format is `{namespace}-{middleware-name}@kubernetescrd`. Adjust the
namespace prefix if the middleware is not in the `traefik` namespace.

1. To support annotations in the ingress template, add the following to
   `charts/ingress/values.yaml` and `charts/ingress/templates/ingress.yaml`:

In `charts/ingress/values.yaml`:

```yaml
annotations: {}
```

In `charts/ingress/templates/ingress.yaml` (under `metadata:`):

```yaml
  {{- with .Values.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
```

---

### TLS Certificate Options

The `traefik-tls` Kubernetes Secret must exist before `helm install`. The setup
scripts generate a self-signed certificate by default (sufficient for initial
testing). For production, replace it with one of the options below.

#### Option A — CA-Signed Certificate (Recommended for Production)

If you have a certificate from your CA or a public provider (e.g. DigiCert,
Sectigo, Azure-managed cert):

```powershell
# kubectl approach
kubectl create secret tls traefik-tls `
    --cert=path/to/fullchain.pem `
    --key=path/to/privkey.pem `
    --namespace threesixty `
    --dry-run=client -o yaml | kubectl apply -f -
```

The secret must contain:

- `tls.crt` — the full certificate chain (leaf + intermediates)
- `tls.key` — the private key (unencrypted PEM)

#### Option B — Let's Encrypt via cert-manager (Automated Renewal)

Install cert-manager on the cluster:

```bash
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
    --namespace cert-manager --create-namespace \
    --set installCRDs=true
```

For **public clusters** (HTTP-01 challenge — ACME server must reach port 80):

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          ingress:
            class: traefik
```

For **internal/private clusters** (DNS-01 challenge via Azure DNS — recommended
for AKS internal deployments where port 80 is not reachable from the internet):

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - dns01:
          azureDNS:
            resourceGroupName: your-dns-resource-group
            subscriptionID: your-subscription-id
            hostedZoneName: your-domain.com
            environment: AzurePublicCloud
            managedIdentity:
              clientID: your-managed-identity-client-id
```

Once the issuer is configured, annotate the ingress to request a certificate
automatically. Add to `values-production.yaml`:

```yaml
ingress:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    traefik.ingress.kubernetes.io/router.middlewares: "traefik-redirect-to-https@kubernetescrd"
  tls:
    - secretName: traefik-tls   # cert-manager will populate this secret
      hosts:
        - your-domain.com
```

#### Option C — Azure App Service Managed Certificate / Azure Key Vault

For AKS deployments, the Secrets Store CSI Driver with Azure Key Vault can
inject a certificate stored in Key Vault directly as a Kubernetes Secret:

```bash
# Store your certificate in Key Vault
az keyvault certificate import \
    --vault-name your-keyvault \
    --name threesixty-tls \
    --file fullchain.pfx

# Create a SecretProviderClass to sync it as a Kubernetes Secret
# (requires Secrets Store CSI Driver and Azure Key Vault provider)
```

This approach integrates with Azure Managed Identity (no static credentials) and
supports automatic renewal for certificates issued by Azure Certificate Authority.

---

## NetworkPolicies

NetworkPolicies implementing a default-deny-ingress baseline are included in
`templates/networkpolicies.yaml`. They are **disabled by default** to avoid
disrupting existing deployments.

Enable them in `values-production.yaml`:

```yaml
networkPolicy:
  enabled: true
  ingressNamespace: "traefik"   # namespace your ingress controller runs in
```

Verify the Traefik namespace on your cluster before enabling:

```bash
kubectl get ns | grep traefik
```

The following ingress paths are permitted when NetworkPolicies are active:

| Source | Destination | Port |
| --- | --- | --- |
| Admin | MongoDB | 27017 |
| Admin | RabbitMQ | 5672 |
| Admin | SCIM | 8083 |
| SCIM | MongoDB | 27017 |
| SCIM | RabbitMQ | 5672 |
| OI-RAG | OpenSearch | 9200 |
| OI-RAG | Ollama | 11434 |
| Remote Agent | Admin (gRPC) | 50052 |
| Ingress controller | Admin / Discovery | 8080 |
| Ingress controller | SCIM | 8083 |
| OpenSearch Dashboards | OpenSearch | 9200 |

All other ingress is denied by default.

---

## Security Checklist

Before deploying to production:

- [ ] Run `kubectl-create-secrets.ps1` (or `aks-create-secrets.ps1`) with strong, unique passwords for all services
- [ ] Confirm `values-production.yaml` is **not** tracked by git (`git status` should not show it)
- [ ] Set `ingress.host` to your actual domain
- [ ] Replace the self-signed TLS certificate with a CA-signed or Let's Encrypt certificate
- [ ] Add the HTTPS redirect middleware annotation to the ingress
- [ ] Set `networkPolicy.enabled: true` and confirm `networkPolicy.ingressNamespace` matches your Traefik namespace
- [ ] Set `elasticsearch.enabled: false` (not used — OpenSearch is the search backend)
- [ ] Confirm `OPENSEARCH_USER` in `values-production.yaml` is set to `admin`
- [ ] Set `REMOTE_AGENT_NAME` and `REMOTE_SERVER_URL` in the hybridsearch config
- [ ] Verify all secrets were created: `make verify-secrets`
- [ ] Review open items in [REMEDIATION-RECOMMENDATIONS.md](REMEDIATION-RECOMMENDATIONS.md)

---

## Troubleshooting

```bash
# List all secrets in the namespace
kubectl get secrets -n threesixty

# Inspect a specific secret (base64-encoded values)
kubectl get secret threesixty-stack-admin-secret -n threesixty -o yaml

# Decode a specific key
kubectl get secret threesixty-stack-admin-secret -n threesixty \
    -o jsonpath='{.data.MONGODB_URI}' | base64 -d

# Check which environment variables a pod sees
kubectl exec -n threesixty deployment/threesixty-stack-admin \
    -- env | grep -E 'MONGO|RABBIT|SCIM'

# Verify NetworkPolicies are applied
kubectl get networkpolicy -n threesixty

# Check ingress TLS certificate details
kubectl get secret traefik-tls -n threesixty -o jsonpath='{.data.tls\.crt}' \
    | base64 -d | openssl x509 -noout -dates -subject
```
