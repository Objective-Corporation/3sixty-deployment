# Changelog

All notable changes to the 3Sixty Helm chart project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.0] - 2026-03-16

### Added
- **Traefik 39.0.5 bundled as a subchart dependency** — no separate ingress controller installation required. Controlled by `traefik.enabled` (default: false in values.yaml, true in values-production.yaml.template).
- **Default Traefik ports**: 7070 (HTTP) and 7443 (HTTPS) to avoid conflicts with host services on 80/443. Change `exposedPort` values for production AKS/EKS deployments.
- **Per-component `enabled` flags for hybridsearch subchart**: `hybridsearch.remoteagent.enabled` and `hybridsearch.oirag.enabled`. Allows disabling Remote Agent until a valid token is registered in the admin UI.
- **`--force-conflicts` flag on `make upgrade`** to resolve Helm server-side apply field ownership conflicts without deleting/recreating pods.

### Fixed
- **SCIM startup/readiness/liveness probes** changed from `httpGet /scim/v2/health` (returns 401) to `tcpSocket` — probes no longer fail on unauthenticated health endpoint.
- **`podSecurityContext` and `containerSecurityContext` set to `{}` for threesixty subchart** — Tomcat images require root for WAR chmod at startup; gosu user-switch requires CAP_SETUID/CAP_SETGID. Tracked as security backlog item H-02a pending image rebuild.
- **IngressClass name corrected to `threesixty-stack-traefik`** (Helm release-prefixed) in values-production.yaml.
- **HTTP→HTTPS redirect config corrected** for Traefik v3 chart schema (`ports.web.http.redirections.entryPoint` instead of deprecated `redirectTo`).

### Changed
- **`networkPolicy.ingressNamespace` updated to `threesixty`** (Traefik now co-located in the same namespace as the stack).
- **`kubectl-create-secrets.ps1` fixed for PowerShell 5.1 compatibility**: Replaced non-ASCII characters (✓, em-dashes), fixed `@` handling in `--from-literal` arguments, made ECR and TLS steps non-fatal.
- **Chart version bumped to 1.5.0**.

---

## [1.2.1] - 2025-03-05

### Changed - Template File Naming Standardization

Standardized all Helm template file naming to consistent `<resourcetype>-<servicename>.yaml` pattern
for improved developer experience and repository maintainability.

#### Files Renamed (36 total across 5 charts)

**elasticsearch chart (3 files):**
- `deployment.yaml` → `deployment-elasticsearch.yaml`
- `pvc.yaml` → `pvc-elasticsearch.yaml`
- `service.yaml` → `service-elasticsearch.yaml`

**hybridsearch chart (9 files):**
- `oirag-deployment.yaml` → `deployment-oirag.yaml`
- `oirag-service.yaml` → `service-oirag.yaml`
- `oirag-configmap.yaml` → `configmap-oirag.yaml`
- `ollama-deployment.yaml` → `deployment-ollama.yaml`
- `ollama-pvc.yaml` → `pvc-ollama.yaml`
- `ollama-service.yaml` → `service-ollama.yaml`
- `remoteagent-deployment.yaml` → `deployment-remoteagent.yaml`
- `remoteagent-service.yaml` → `service-remoteagent.yaml`
- `remoteagent-configmap.yaml` → `configmap-remoteagent.yaml`

**mongo chart (4 files):**
- `deployment.yaml` → `deployment-mongo.yaml`
- `pvc.yaml` → `pvc-mongo.yaml`
- `service.yaml` → `service-mongo.yaml`
- `init-configmap.yaml` → `init-configmap-mongo.yaml`

**opensearch chart (5 files):**
- `deployment.yaml` → `deployment-opensearch.yaml`
- `pvc.yaml` → `pvc-opensearch.yaml`
- `service.yaml` → `service-opensearch.yaml`
- `dashboard-deployment.yaml` → `deployment-dashboard.yaml`
- `dashboard-service.yaml` → `service-dashboard.yaml`

**threesixty chart (15 files):**
- `admin-deployment.yaml` → `deployment-admin.yaml`
- `admin-service.yaml` → `service-admin.yaml`
- `admin-configmap.yaml` → `configmap-admin.yaml`
- `admin-secret.yaml` → `secret-admin.yaml`
- `discovery-deployment.yaml` → `deployment-discovery.yaml`
- `discovery-service.yaml` → `service-discovery.yaml`
- `discovery-configmap.yaml` → `configmap-discovery.yaml`
- `discovery-secret.yaml` → `secret-discovery.yaml`
- `scim-deployment.yaml` → `deployment-scim.yaml`
- `scim-service.yaml` → `service-scim.yaml`
- `scim-configmap.yaml` → `configmap-scim.yaml`
- `scim-secret.yaml` → `secret-scim.yaml`
- `rabbitmq-deployment.yaml` → `deployment-rabbitmq.yaml`
- `rabbitmq-service.yaml` → `service-rabbitmq.yaml`
- `mongodb-secret.yaml` → `secret-mongodb.yaml`

#### Benefits
- ✅ Alphabetical grouping by resource type in IDE file explorers
- ✅ Easier pattern matching for scripting and automation
- ✅ Clear identification of resource type at a glance
- ✅ Consistent developer experience across all charts
- ✅ Better IDE navigation and search functionality

#### Validation
- Helm template rendering: 0 errors
- All 37 Kubernetes resources present and correct
- No functional changes (pure file renaming)

## [1.2.0] - 2025-03-05

### ConfigMap Architecture Restored with Enhanced Abstraction

This release **restores the ConfigMap-based configuration architecture** after architectural review,
providing improved maintainability, better separation of concerns, and enhanced GitOps workflows.
The implementation uses cleaner patterns than v1.0.0, with range loops for maximum flexibility and
full support for `values-production.yaml` overrides.

#### Architectural Decision

After implementation of v1.1.0 (cross-platform portability via environment variable flattening),
architectural review determined that **ConfigMaps provide superior benefits for Kubernetes-native
deployments**: easier configuration updates, better visibility, improved debugging, cleaner GitOps
diffs, and industry-standard separation of concerns. Cross-platform portability requirement was
re-evaluated in favor of Kubernetes best practices.

#### Added
- **6 ConfigMap Templates** with improved structure:
  - `charts/threesixty/templates/admin-configmap.yaml` (7 environment variables)
  - `charts/threesixty/templates/discovery-configmap.yaml` (2 environment variables)
  - `charts/threesixty/templates/scim-configmap.yaml` (6 environment variables with range loop pattern)
  - `charts/hybridsearch/templates/oirag-configmap.yaml` (15 environment variables with range loop)
  - `charts/hybridsearch/templates/remoteagent-configmap.yaml` (7 environment variables with range loop)
  - `charts/mongo/templates/init-configmap.yaml` (4 env vars + embedded 40-line init script)

- **Range Loop Pattern** for maximum maintainability (scim, oirag, remoteagent):
  ```yaml
  {{- range $key, $value := .Values.env.[component] }}
  {{ $key }}: {{ $value | quote }}
  {{- end }}
  ```
  This pattern eliminates hardcoded keys, making configuration updates require only `values.yaml` changes.

#### Changed
- **All 6 Deployments Refactored** to use `envFrom` ConfigMap references:
  - **admin-deployment.yaml**: Replaced 7 inline env vars with `configMapRef`, kept 2 explicit secrets
  - **discovery-deployment.yaml**: Replaced 2 inline env vars with `configMapRef`  
  - **scim-deployment.yaml**: Replaced inline range loop with `configMapRef`
  - **oirag-deployment.yaml**: Replaced inline range loop with `configMapRef`
  - **remoteagent-deployment.yaml**: Replaced inline range loop with `configMapRef`
  - **mongo-deployment.yaml**: Replaced inline env vars with `configMapRef`, added init script volume mount

- **MongoDB Init Script as ConfigMap Volume**:
  - Reverted to standard `mongo:7.0` image (no custom image needed)
  - Init script (`init-mongo.sh`) embedded in ConfigMap and mounted to `/docker-entrypoint-initdb.d`
  - Better visibility (script in template rather than Docker image)
  - Easier maintenance (edit ConfigMap, no rebuild/push required)

- **Improved Pattern Consistency**:
  ```yaml
  envFrom:
    - configMapRef:
        name: {{ include "[chart].fullname" . }}-[component]-config
    - secretRef:
        name: {{ include "[chart].fullname" . }}-[component]-secret
  ```

#### Removed
- **custom-mongo/ directory** (3 files):
  - `Dockerfile` - No longer needed (using standard mongo:7.0)
  - `init-mongo.sh` - Now embedded in `init-configmap.yaml`
  - `README.md` - Custom image instructions no longer applicable
- **Inline environment variables from deployments** - Moved to ConfigMaps
- **Custom MongoDB image requirement** - Reverted to official mongo:7.0

#### Security
- **Secret Separation Maintained**: All sensitive data remains in Secrets, non-sensitive in ConfigMaps
- **Explicit Secret References**: Passwords and tokens kept as explicit `secretRef` or individual `env` entries
- **No Credential Changes**: All secret handling from v1.0.0 preserved

#### Benefits Over v1.1.0
- ✅ **Easier Updates**: Edit ConfigMap, restart pods - no YAML editing required
- ✅ **Better Visibility**: `kubectl get configmap` shows all configuration clearly
- ✅ **Cleaner GitOps**: Configuration changes show as ConfigMap diffs, not deployment spec changes
- ✅ **Hot Reload Potential**: ConfigMaps can be updated without full redeployment
- ✅ **Improved Debugging**: `kubectl describe configmap` shows all env values in one place
- ✅ **Volume Mounting**: Scripts and files can be mounted (e.g., MongoDB init script)
- ✅ **Industry Standard**: Kubernetes best practice for configuration management
- ✅ **Separation of Concerns**: Config separated from deployment specifications

#### Improvements Over v1.0.0
- **Range Loop Pattern**: scim/oirag/remoteagent use elegant loops instead of hardcoded keys
- **Cleaner Templates**: Reduced deployment template complexity
- **Better Abstraction**: All values sourced from `.Values.env` hierarchy with full override support

#### Migration from v1.1.0

**No Breaking Changes** - Standard Helm upgrade works:

```bash
# Delete custom MongoDB image (if built)
# No longer needed - now using standard mongo:7.0

# Deploy v1.2.0
helm upgrade --install threesixty . -f values-production.yaml

# Verify ConfigMaps created
kubectl get configmap | grep -E "admin-config|discovery-config|scim-config|oirag-config|remoteagent-config|init-config"

# Check deployment references
kubectl describe deployment threesixty-admin | grep -A 5 "Environment Variables from"
```

**Simplified Maintenance**:
- Configuration changes: Edit `values-production.yaml`, run `helm upgrade`
- No custom image builds required
- No Docker registry pushes needed
- Standard kubectl debugging commands work

#### Validation
- ✅ Helm template rendering: 0 errors
- ✅ ConfigMap count: 6 resources created
- ✅ Deployment references: All use `envFrom configMapRef`
- ✅ MongoDB init: Script properly mounted as volume
- ✅ Secrets: Properly separated and referenced
- ✅ Conditional logic: All preserved (afs vs 3sixty, scim.enabled)

**Rationale**: ConfigMap architecture provides superior maintainability, debugging, and GitOps
workflows for Kubernetes deployments. The improved implementation uses range loops for flexibility
while maintaining all conditional logic and security separation from v1.0.0.

---

## [1.0.0] - 2025-03-05

### Major Release - Production Ready

This represents the first production-ready release of the 3Sixty Helm chart with comprehensive
versioning documentation, security hardening, and modern Kubernetes patterns.

#### Added
- **Comprehensive Versioning Documentation**: All Chart.yaml files now include detailed headers explaining:
  - Semantic versioning rules (MAJOR.MINOR.PATCH)
  - When to update chart version vs appVersion
  - Helm upgrade behavior and version tracking
  - Subchart versioning independence
  - Dependency version management
- **Kubernetes DNS Patterns**: All internal service communication uses K8s DNS (service-name.namespace.svc.cluster.local)
- **Credential Abstraction**: 37+ credential values abstracted from templates to values-production.yaml
- **Ollama LLM Service**: Configured with auto-pull for llama3.2:3b model
- **Global Image Pull Secrets**: Centralized ECR authentication pattern using imagePullSecrets
- **Template Synchronization**: All templates synchronized with production configuration file

#### Changed
- **Chart Version**: Bumped from 0.1.0 to 1.0.0 (production-ready milestone)
- **All Subchart Versions**: Updated from 0.1.0 to 1.0.0:
  - mongo: 1.0.0 (MongoDB 8.0.11)
  - threesixty: 1.0.0 (3Sixty 5.1.1)
  - opensearch: 1.0.0 (OpenSearch 2.4.1)
  - elasticsearch: 1.0.0 (Elasticsearch 7.17.0)
  - hybridsearch: 1.0.0 (Ollama 0.7.0 + OI-RAG 5.0.1-RC3)
- **Parent Chart Dependencies**: All dependency versions updated to 1.0.0 with inline comments
- **Chart Descriptions**: Enhanced with detailed component descriptions

#### Security
- **Password Randomization**: All weak internal credentials upgraded to 24-character secure random passwords:
  - MongoDB passwords (admin, discovery, scim, root)
  - RabbitMQ default user password
  - OpenSearch admin password (hybridsearch)
  - API bearer tokens (hybridsearch)
- **Values Separation**: Sensitive credentials isolated in git-ignored values-production.yaml
- **Template Hardening**: Removed all hardcoded credentials from template files

#### Documentation
- **CHANGELOG.md**: Created to track version history (this file)
- **Versioning Guide**: Comprehensive inline documentation in all Chart.yaml files
- **README.md**: Updated to reflect current deployment patterns (separate commit)
- **.claude**: Project intent and status documentation for AI assistant

#### Migration Notes
After upgrading to version 1.0.0, you must run:
```bash
helm dependency update
```

This ensures the parent chart recognizes the updated subchart versions.

---

## [0.1.0] - Previous Versions

Earlier developmental versions focused on:
- Basic 3Sixty stack deployment
- MongoDB integration
- OpenSearch setup
- Elasticsearch legacy support
- Initial hybridsearch components

Versioning documentation and production hardening were added in version 1.0.0.
