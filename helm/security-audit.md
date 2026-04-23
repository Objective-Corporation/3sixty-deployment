# 3Sixty Helm Chart Security Audit Report

| Field | Value |
|---|---|
| **Audit Date** | 2026-03-16 |
| **Auditor** | Security Auditor Agent (claude-opus-4-6) |
| **Scope** | Full Helm chart review for AKS production deployment |
| **Chart Version** | 1.4.0 |
| **App Version** | 5.2.0 |
| **Branch** | main |

---

## Executive Summary

This audit reviewed 50+ template, values, and script files across the 3Sixty Helm chart project (parent chart with 6 subcharts). The project demonstrates a maturing security posture with external secret management via setup scripts, pod security contexts, and resource limits on all deployments. However, several critical and high-severity findings remain that must be addressed before production deployment.

**Finding Summary:**

| Severity | Count |
|---|---|
| CRITICAL | 3 |
| HIGH | 8 |
| MEDIUM | 7 |
| LOW | 6 |
| **Total** | **24** |

---

## CRITICAL Findings

### C-01: Production Credentials Committed to Git (values-production.yaml)

- **File:** `helm/values-production.yaml`
- **Lines:** 57-58 (RabbitMQ), 64 (SCIM), 72 (MongoDB), 189 (password reference table)
- **Status:** values-production.yaml appears in `git status` as modified (`M values-production.yaml`), meaning it is tracked by git despite the `.gitignore` entry. The `.gitignore` contains `values-production.yaml` but the file was likely added before the gitignore rule was created.
- **Impact:** All production passwords are visible in the git history and to anyone with repository access: MongoDB password `Db7!xN4@pQ9#mW2$vK6+zL3*hR`, RabbitMQ password `Mq8#zK2@pW9vX5!nR7jL4$hQ`, SCIM password `Sc3$mP9@sW2#dX6!vK8nQ5+jL`, and OpenSearch password `F$kuBpOWx5SshqNAlC&yLfoX`.
- **Evidence:** Git status shows `M values-production.yaml` (modified, tracked). Lines 182-190 contain a plaintext password reference table with all credentials.
- **Remediation:**
  1. Immediately rotate ALL credentials listed in that file (MongoDB, RabbitMQ, SCIM, OpenSearch).
  2. Run `git rm --cached values-production.yaml` to untrack the file without deleting it locally.
  3. Commit that removal.
  4. Consider running `git filter-branch` or `BFG Repo-Cleaner` to purge credentials from history.
  5. Verify the `.gitignore` rule is effective after untracking.

### C-02: Helm-Managed Secrets Store Credentials in etcd via values-production.yaml

- **Files:** `charts/threesixty/templates/secret-admin.yaml`, `secret-discovery.yaml`, `secret-scim.yaml`, `secret-mongodb.yaml`
- **Impact:** Four Kubernetes Secrets are rendered by Helm from values passed through `values-production.yaml`. This means: (a) credentials flow through Helm's release storage in etcd unencrypted (unless etcd encryption at rest is configured), (b) `helm get values` exposes all passwords to anyone with Helm RBAC, (c) credentials exist in the Helm release secret (`sh.helm.release.v1.*`) in plaintext base64.
- **Detail:** The admin-secret (line 8) embeds a full MongoDB connection URI with username and password inline. The scim-secret (line 10) does the same for the SCIM MongoDB connection string.
- **Remediation:**
  1. Migrate all four Helm-managed secrets to external secrets created by the setup scripts (same pattern as rabbitmq-secret, mongo-init-secret, oirag-secret, remoteagent-secret).
  2. Remove `threesixty.rabbitmq.password`, `threesixty.scim.credentials.password`, `threesixty.mongodb.password`, and `threesixty.oauth2.clientSecret` from values files entirely.
  3. Alternatively, adopt a secrets management operator (e.g., External Secrets Operator with Azure Key Vault) to inject secrets from a vault.
  4. Enable etcd encryption at rest on the AKS cluster as a defense-in-depth measure.

### C-03: CORS Wildcard on OI-RAG API Allows Cross-Origin Abuse

- **File:** `charts/hybridsearch/values.yaml`, line 14
- **Value:** `CORS_ALLOW_ORIGINS: "*"`
- **Impact:** The OI-RAG service accepts requests from any origin. If the OI-RAG service is reachable (even via ingress path traversal or SSRF), an attacker's website can make authenticated cross-origin requests to the API using the user's browser context, potentially extracting data from the search/RAG pipeline.
- **Remediation:** Restrict `CORS_ALLOW_ORIGINS` to the specific domain(s) that need access (e.g., `https://threesixty.objective.com`).

---

## HIGH Findings

### H-01: No NetworkPolicies -- All Pods Can Communicate Freely

- **Scope:** Entire chart (all subcharts)
- **Impact:** Any compromised pod can reach any other pod in the namespace (and potentially across namespaces). MongoDB (27017), OpenSearch (9200/9300), RabbitMQ (5672/15672), Ollama (11434), and all application ports are reachable from every pod.
- **Remediation:**
  1. Create NetworkPolicy resources for each subchart restricting ingress to only the pods that need access.
  2. Example: MongoDB should only accept connections from admin, discovery, and scim pods. OpenSearch should only accept connections from oirag and dashboards pods. RabbitMQ should only accept from admin and scim.
  3. Apply a default-deny ingress policy for the namespace.

### H-02: Default ServiceAccount with Token Automounting on All Pods

- **Scope:** All deployment templates (none specify `serviceAccountName` or `automountServiceAccountToken: false`)
- **Impact:** Every pod mounts the default service account token at `/var/run/secrets/kubernetes.io/serviceaccount/token`. If a container is compromised, the attacker gets a Kubernetes API token that may have permissions to list/read secrets, pods, and other resources in the namespace.
- **Remediation:**
  1. Create a dedicated ServiceAccount for each subchart (or a shared minimal one) with `automountServiceAccountToken: false`.
  2. Set `automountServiceAccountToken: false` on every pod spec that does not need Kubernetes API access (which is all of them in this chart).

### H-03: Ollama Runs as Root (UID 0) Without runAsNonRoot or Capability Restrictions

- **File:** `charts/hybridsearch/values.yaml`, lines 110-115
- **File:** `charts/hybridsearch/templates/deployment-ollama.yaml`
- **Impact:** The Ollama container runs as `runAsUser: 0` with `runAsNonRoot` not set (defaults to false) and without `capabilities.drop: ["ALL"]`. A container escape from Ollama would grant root access to the node. The comment acknowledges this is required by the official image.
- **Remediation:**
  1. Build a custom Ollama image that runs as non-root with model storage in a non-root-owned directory, OR
  2. Use an init container running as root to set up the model directory permissions, then run the main container as non-root, OR
  3. At minimum, add `readOnlyRootFilesystem: true` (with writable emptyDir/PVC mounts), `capabilities.drop: ["ALL"]`, and the minimum required capabilities back.

### H-04: Elasticsearch Subchart Has No Security Controls

- **File:** `charts/elasticsearch/templates/deployment-elasticsearch.yaml`
- **File:** `charts/elasticsearch/values.yaml`
- **Impact:** The Elasticsearch deployment has: no `securityContext` at pod or container level (runs as root by default), no resource limits, no health probes, no authentication, and the image tag `7.17.0` is over 4 years old with known CVEs. While `elasticsearch.enabled: false` in the default values.yaml, it is `enabled: true` in `values-production.yaml` (line 36).
- **Remediation:**
  1. If Elasticsearch is not needed in production, ensure it is set to `enabled: false` in the production values and remove the `enabled: true` override from `values-production.yaml` line 36.
  2. If it is needed, add pod/container security contexts, resource limits, health probes, and upgrade the image to a current supported version.

### H-05: Self-Signed TLS Certificate Generated by Setup Scripts

- **Files:** `kubectl-create-secrets.ps1` (lines 180-185), `aks-create-secrets.ps1` (lines 262-267)
- **Impact:** Both setup scripts generate a self-signed RSA 2048-bit certificate with 365-day validity and `/CN=domain` only. Self-signed certificates provide encryption but no identity verification, enabling MITM attacks. Additionally, RSA 2048 is below current best practice for new deployments.
- **Remediation:**
  1. For production, use a CA-signed certificate (Azure-managed cert, Let's Encrypt via cert-manager, or organizational CA).
  2. Install cert-manager in the cluster and configure it with an ACME issuer or Azure DNS solver for automatic certificate rotation.
  3. If self-signed must be used temporarily, upgrade to RSA 4096 or ECDSA P-256.

### H-06: No Inter-Service TLS (All Internal Communication is Plaintext HTTP)

- **Evidence:** ConfigMap values show all internal URLs use `http://`:
  - `configmap-oirag.yaml` line 14-15: `http://...ollama:11434/v1`, `http://...opensearch:9200`
  - `configmap-remoteagent.yaml` line 15: `http://...admin:8080/3sixty-admin`
  - `configmap-discovery.yaml` line 9: `http://...admin:8080/...`
  - `values-production.yaml` line 121-122: hardcoded `http://` URLs
- **Impact:** All inter-pod traffic (including MongoDB credentials in connection URIs, bearer tokens, OAuth2 tokens) is transmitted in plaintext. Any network-level attacker (compromised pod, ARP spoofing, or misconfigured CNI) can sniff credentials.
- **Note:** GRPC_SERVER_SSL is explicitly set to `"false"` (threesixty values, line 123).
- **Remediation:**
  1. Enable TLS on OpenSearch (it supports it natively with the security plugin).
  2. Enable TLS for gRPC (`GRPC_SERVER_SSL: "true"`).
  3. Consider a service mesh (Istio, Linkerd) for automatic mTLS between all pods.

### H-07: RabbitMQ Management Port 15672 Exposed via ClusterIP Service

- **File:** `charts/threesixty/templates/service-rabbitmq.yaml`, lines 14-16
- **File:** `charts/threesixty/values.yaml`, line 38
- **Impact:** The RabbitMQ management UI (HTTP-based admin console) is accessible to any pod in the cluster. The management API allows full queue/exchange/user management and can expose message contents.
- **Remediation:**
  1. Remove port 15672 from the service definition unless actively needed for monitoring.
  2. If management access is needed, restrict it via NetworkPolicy to only authorized pods/operators.
  3. Consider switching to a non-management RabbitMQ image (`rabbitmq:4.1` instead of `rabbitmq:4.1-management`).

### H-08: Credential Duplication Between Helm Values and External Secrets Creates Sync Risk

- **File:** `values-production.yaml`, lines 54-58 (comment: "keep these in sync")
- **Impact:** RabbitMQ credentials exist in two places: (a) the external `{release}-rabbitmq-secret` created by setup scripts, and (b) the Helm-managed `{release}-admin-secret` and `{release}-scim-secret` rendered from `values-production.yaml`. If they drift out of sync, the admin/scim pods will have different credentials than RabbitMQ itself, causing authentication failures that are difficult to diagnose. The same applies to MongoDB credentials (external init-secret vs Helm-managed admin-secret/scim-secret).
- **Remediation:** Consolidate all credentials into a single source (either all external secrets or a secrets operator). Eliminate the need to set the same password in two places.

---

## MEDIUM Findings

### M-01: Ollama Image Uses `latest` Tag

- **File:** `charts/hybridsearch/values.yaml`, line 95
- **Value:** `tag: latest`
- **Impact:** The `latest` tag is mutable and can change unexpectedly between deployments. Combined with `pullPolicy: IfNotPresent`, this means: (a) new nodes will pull whatever `latest` points to at that time, (b) different nodes may run different versions, (c) no reproducibility or rollback capability, (d) a supply chain compromise of the `ollama/ollama:latest` image would be deployed automatically.
- **Remediation:** Pin Ollama to a specific version tag (e.g., `ollama/ollama:0.5.4`).

### M-02: No PodDisruptionBudgets

- **Scope:** All subcharts
- **Impact:** During node drains or cluster upgrades, all replicas of any component can be evicted simultaneously, causing total service outage.
- **Remediation:** Add PodDisruptionBudgets with `minAvailable: 1` for each critical component (admin, discovery, MongoDB, OpenSearch, RabbitMQ).

### M-03: OpenSearch Transport Port 9300 Exposed on Service

- **File:** `charts/opensearch/templates/service-opensearch.yaml`, lines 13-15
- **Impact:** The OpenSearch transport port (used for inter-node cluster communication) is exposed on the ClusterIP service. For a single-node deployment, this port is unnecessary and increases the attack surface.
- **Remediation:** Remove port 9300 from the service definition. The `transport.host=127.0.0.1` setting in the cluster args already restricts transport to localhost, but the service still routes traffic to it.

### M-04: OpenSearch Dashboards Port 5601 Accessible Without Ingress Restriction

- **File:** `charts/opensearch/templates/service-dashboard.yaml`
- **Impact:** OpenSearch Dashboards is exposed on a ClusterIP service (port 5601) with no ingress route but reachable from any pod in the namespace. Dashboards provides full admin access to OpenSearch data, index management, and security configuration.
- **Remediation:** Add NetworkPolicy restricting access to authorized admin pods only. Consider whether Dashboards should be deployed in production at all.

### M-05: MongoDB Init Script Uses Shell Variable Expansion (Injection Risk)

- **File:** `charts/mongo/templates/init-configmap-mongo.yaml`, lines 25-46
- **Impact:** The init script uses unquoted `${MONGO_INITDB_ROOT_USERNAME}` and `${MONGO_INITDB_ROOT_PASSWORD}` in a `mongosh` heredoc. If a username or password contains shell metacharacters (e.g., backticks, `$(...)`, or double quotes), they could cause shell injection during the init script execution. The values come from the external secret, which is controlled by the admin, but this is a defense-in-depth concern.
- **Remediation:** Quote the variables or use mongosh's `--eval` with proper escaping instead of a heredoc.

### M-06: readOnlyRootFilesystem Not Set on Any Container

- **Scope:** All deployment templates
- **Impact:** All containers have writable root filesystems, which allows an attacker who gains code execution to modify binaries, install tools, or tamper with the application.
- **Remediation:** Add `readOnlyRootFilesystem: true` to all container security contexts and mount writable `emptyDir` volumes only where the application needs write access (e.g., `/tmp`, log directories).

### M-07: aks-create-secrets.ps1 Writes TLS Secret YAML to Disk (temp-tls-secret.yaml)

- **File:** `aks-create-secrets.ps1`, lines 305-306
- **Impact:** The script writes a YAML file containing base64-encoded TLS private key material to the current directory (`temp-tls-secret.yaml`). While line 534 attempts cleanup, if the script is interrupted or fails before cleanup, the private key remains on disk.
- **Remediation:** Use a secure temporary file path (system temp directory) and ensure cleanup in a `try/finally` block.

---

## LOW Findings

### L-01: RC (Release Candidate) Image Tags Used in Default Values

- **Files:**
  - `charts/threesixty/values.yaml` line 8: `tag: 5.0.3-RC1`
  - `charts/hybridsearch/values.yaml` line 8: `tag: 5.0.1-RC3`
  - `charts/hybridsearch/values.yaml` line 56: `tag: 5.0.2-RC1`
- **Impact:** Release candidate images may contain known bugs or incomplete features. Using RC images in production increases risk.
- **Remediation:** Ensure all image tags are GA (General Availability) releases before production deployment.

### L-02: OPENAI_API_KEY Set to Hardcoded Placeholder "no-key"

- **File:** `charts/hybridsearch/values.yaml`, line 17
- **Value:** `OPENAI_API_KEY: "no-key"`
- **Impact:** This value is deployed to the ConfigMap as a plaintext env var. If an actual API key is ever needed, this pattern of putting it in a ConfigMap (vs Secret) would leak it.
- **Remediation:** If this variable will ever hold a real key, move it to a Secret. Document that the current value is intentionally non-functional for the Ollama-only configuration.

### L-03: No Helm Chart Integrity Verification (chart provenance)

- **Scope:** Parent Chart.yaml
- **Impact:** There is no `.prov` file or chart signing. Anyone with repository write access can modify chart templates without cryptographic verification.
- **Remediation:** Consider signing Helm charts with `helm package --sign` for production deployments.

### L-04: ECR Token Has 12-Hour Expiry -- No Automated Rotation

- **Files:** `kubectl-create-secrets.ps1` line 132, `aks-create-secrets.ps1` line 210
- **Impact:** The ECR docker-registry secret uses a token from `aws ecr get-login-password` which expires after 12 hours. After expiry, new pod scheduling will fail if it needs to pull images.
- **Remediation:** Deploy an ECR credential helper (e.g., `ecr-credential-provider` kubelet plugin or a CronJob that refreshes the secret).

### L-05: Single-Replica Deployments for All Stateful Services

- **Scope:** All subcharts specify `replicas: 1`
- **Impact:** No high availability for any component. A single pod failure causes complete service outage for that component.
- **Note:** This is acceptable for initial deployment but should be planned for production scaling.
- **Remediation:** Plan for multi-replica deployments of stateless services (admin, discovery, scim, oirag) and evaluate clustering for stateful services (MongoDB replica set, OpenSearch multi-node).

### L-06: Ingress Does Not Enforce HTTPS Redirect

- **File:** `charts/ingress/templates/ingress.yaml`
- **Impact:** The ingress defines TLS but does not include annotations to force HTTP-to-HTTPS redirect (e.g., `traefik.ingress.kubernetes.io/router.middlewares` for redirect). Users accessing via HTTP would send credentials in plaintext.
- **Remediation:** Add Traefik middleware annotations or a global redirect configuration to ensure all HTTP traffic is redirected to HTTPS.

---

## Positive Findings

The following security measures are already properly implemented:

1. **External secret management** for infrastructure credentials (MongoDB init, RabbitMQ, OpenSearch, OI-RAG, Remote Agent) via dedicated setup scripts.
2. **Pod security contexts** on all deployments except Elasticsearch (which is disabled by default): `runAsNonRoot: true`, specific UIDs, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`.
3. **Resource requests and limits** on all active deployments, preventing resource exhaustion attacks.
4. **Health probes** (readiness, liveness, startup) on all deployments.
5. **ClusterIP services** for all components (no LoadBalancer or NodePort exposure).
6. **PVC retention annotations** (`helm.sh/resource-policy: keep`) preventing accidental data loss.
7. **Image pull secrets** configured for private ECR registry.
8. **Separation of ConfigMaps and Secrets** -- credentials are not placed in ConfigMaps (with explicit comments warning against doing so).
9. **Template-based production values** (`values-production.yaml.template`) with CHANGE_ME placeholders for safe distribution.
10. **Ingress host field** properly set (not wildcard) to restrict routing to the intended domain.

---

## Remediation Priority Roadmap

### Immediate (Before Production Deployment -- Week 1)

| ID | Action | Effort |
|---|---|---|
| C-01 | Untrack values-production.yaml from git, rotate all credentials | 2 hours |
| C-02 | Migrate remaining Helm-managed secrets to external secrets | 4 hours |
| C-03 | Restrict CORS_ALLOW_ORIGINS to specific domain | 15 minutes |
| H-04 | Disable Elasticsearch in values-production.yaml | 5 minutes |
| H-02 | Add automountServiceAccountToken: false to all pod specs | 1 hour |

### Short-Term (Within 30 Days)

| ID | Action | Effort |
|---|---|---|
| H-01 | Implement default-deny NetworkPolicies for the namespace | 4 hours |
| H-05 | Deploy cert-manager with proper CA-signed certificates | 4 hours |
| H-07 | Remove management port 15672 from RabbitMQ service | 15 minutes |
| H-08 | Consolidate credential sources to single external secrets | 4 hours |
| M-01 | Pin Ollama image to specific version | 15 minutes |
| M-06 | Add readOnlyRootFilesystem to all containers | 2 hours |
| L-06 | Add HTTPS redirect to ingress | 30 minutes |

### Medium-Term (Within 90 Days)

| ID | Action | Effort |
|---|---|---|
| H-03 | Build custom non-root Ollama image or init container approach | 1 day |
| H-06 | Enable inter-service TLS (or deploy service mesh) | 2-3 days |
| M-02 | Add PodDisruptionBudgets | 1 hour |
| M-03 | Remove OpenSearch transport port from service | 15 minutes |
| M-04 | Add NetworkPolicy for OpenSearch Dashboards | 30 minutes |
| M-05 | Harden MongoDB init script against injection | 1 hour |
| L-04 | Deploy ECR credential rotation automation | 2 hours |

### Long-Term (Within 6 Months)

| ID | Action | Effort |
|---|---|---|
| - | Adopt External Secrets Operator with Azure Key Vault | 2-3 days |
| - | Evaluate service mesh (Istio/Linkerd) for mTLS | 1 week |
| L-05 | Multi-replica deployments and stateful service clustering | 1-2 weeks |
| L-03 | Implement Helm chart signing | 2 hours |

---

## Compliance Notes

### SOC 2 / ISO 27001 Gaps

- **Access Control (CC6.1/A.9):** Default service accounts with auto-mounted tokens violate least-privilege. No RBAC scoping.
- **Encryption (CC6.7/A.10):** No encryption in transit between services. Credentials in etcd potentially unencrypted at rest.
- **Change Management (CC8.1/A.12):** Mutable `latest` tag and RC images undermine change control.
- **Network Security (CC6.6/A.13):** No network segmentation within the namespace.

### NIST 800-53 Relevant Controls

- **SC-8 (Transmission Confidentiality):** Plaintext HTTP between pods fails this control.
- **SC-28 (Protection of Information at Rest):** Credentials in etcd and Helm release objects need encryption at rest.
- **AC-6 (Least Privilege):** Root containers and default service accounts violate this control.
- **CM-7 (Least Functionality):** Exposed management ports and transport ports violate this control.

---

*End of audit report. Next review recommended after remediation of CRITICAL and HIGH findings.*
