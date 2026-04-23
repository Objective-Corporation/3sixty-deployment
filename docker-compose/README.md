# 3Sixty Local Development

This repository contains everything you need to run all 3Sixty services locally via Docker Compose.

---

## Prerequisites

- **Docker** ≥ 20.10
- **Docker Compose** ≥ 1.29
- **[AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)** ≥ 2
- **[ngrok](https://ngrok.com/downloads)** ≥ 3.11 (Optional)
- **[Cloudflare Tunnel (cloudflared)](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/)** ≥ 2025.5.0 (Optional)
---

## Configuration

_All `.env.*` files are excluded from Git. You’ll need to copy and rename the exising sample.env.* files first._

| Filename         | Purpose                                |
|------------------|----------------------------------------|
| `.env.admin`     | Environment for Admin webapp           |
| `.env.discovery` | Environment for Discovery service      |
| `.env.mongo`     | Environment for MongoDB initialization |
| `.env.oirag`     | Environment for RAG/Agent service      |
| `.env.rabbitmq`  | RabbitMQ credentials & settings        |
| `.env.scim`      | SCIM server configuration              |
| `.env.oi-agent`  | Environment for OI remote agent        |

Place each file in the current folder before starting the stack.

You can leave the default values as they are. 
Make sure you set up values in `.env.discovery`
```
CLIENT_ID=
TENANT_ID=
CLIENT_SECRET=
```

Make sure to change `REMOTE_AGENT_TOKEN` and `REMOTE_AGENT_NAME` after a new remote agent is created in `.env.oi-agent`

### Reusing an Existing MongoDB Docker Volume (Optional)
To reference an existing shared Docker volume in your `docker-compose.yaml`, specify the volume name using the `name` field:
```yaml
  mongo_data:
    name: docker_mongo_data
```

### Line Endings for Shell Scripts (when running on Windows)
📝Important: All shell scripts (e.g. init-mongo.sh) must use Unix-style LF line endings, not Windows CRLF.
CRLF endings will lead to errors like:
```text
/bin/sh^M: bad interpreter: No such file or directory
```
In the bottom-right corner of the text editor (VS Code), you'll see the current line ending format (e.g., CRLF or LF).
Change Line Endings: Click on this indicator and select LF - Unix and macOS (\n) from the dropdown menu.

---

## Get a cert & key
To terminate TLS in Nginx you’ll need to obtain or generate a certificate + key.
For local testing you can self-sign:
```bash
mkdir nginx/certs
openssl req -x509 -newkey rsa:2048 -days 365 \
  -nodes \
  -keyout nginx/certs/tls.key \
  -out nginx/certs/tls.crt \
  -subj "/CN=localhost"
```

---

## Launch All Services
Before launching the services, ensure you are authenticated with AWS ECR to pull the necessary Docker images:
```bash
aws configure
# Enter your credentials and region when prompted:
# AWS Access Key ID [None]: <your-access-key-id>
# AWS Secret Access Key [None]: <your-secret-access-key>
# Default region name [None]: ap-southeast-2
# Default output format [None]: json

aws ecr get-login-password --region ap-southeast-2 | docker login --username AWS --password-stdin 782396859527.dkr.ecr.ap-southeast-2.amazonaws.com
```

Once your .env.* files are in place, simply:
```bash
docker compose up -d
```

Under the covers this will:
- nginx-proxy routes traffic on ports 80/443 using nginx/nginx.conf
- threesixty-admin and threesixty-discovery
- MongoDB, Elasticsearch, OpenSearch + Dashboard
- RabbitMQ & SCIM server for user provisioning
- Ollama + 3sixty-rag (your RAG/agent service) on the `threesixty` network

After remote agent is configured (`.env.oi-agent`) start the OI Remote Agent:
```bash
docker compose -f docker-compose.oi-agent.yaml up -d
```

---

## Access URLs
| Service              | URL                                                                                      |
|----------------------|------------------------------------------------------------------------------------------|
| Admin UI             | [https://localhost/3sixty-admin/](https://localhost/3sixty-admin/)                       |
| Discovery UI         | [https://localhost/3sixty-discovery/](https://localhost/3sixty-discovery/)               |
| OpenSearch Dashboard | [https://localhost/opensearch-dashboard/](https://localhost/opensearch-dashboard/)       |
| Kibana (optional)    | [https://localhost/kibana](https://localhost/kibana) - requires `make elasticsearch-start` |
| RabbitMQ Management  | [http://localhost:15672](http://localhost:15672)                                         |

Certificates are loaded from `./nginx/certs/tls.crt & ./nginx/certs/tls.key`

---

## Public URL Requirement for SCIM and Microsoft Copilot Agent
Certain services require your local environment to be accessible via a public URL:

### 🔗 Why is a Public URL Needed?
* SCIM User Provisioning: Microsoft Entra ID (Azure AD) needs to reach your SCIM API endpoint to sync users. This requires a stable, publicly accessible URL.
* Microsoft Copilot Agent: The remote agent must expose its endpoint to external Microsoft services, which cannot communicate with localhost or private IPs.

### 🚀 How to Set Up a Public URL
Use a tunneling service like Ngrok or Cloudflare Tunnel to expose your local environment.

**Option 1: Using Ngrok**
```bash
ngrok http 443
```
This will generate a public HTTPS URL forwarding to your local port 443 (TLS-terminated by Nginx). Example:
```bash
https://abc123.ngrok.io → https://localhost
```
**Option 2: Using Cloudflare Tunnel (More Stable)**
If you have a custom domain, you can configure a Cloudflare Tunnel:
```bash
cloudflared tunnel --url https://localhost
```
### 🧷 Making the URL Persistent
- Ngrok: Use the --subdomain flag to specify a fixed subdomain:
```bash
ngrok http --subdomain=mydomain 443
```
- Cloudflare Tunnel: Set up a persistent subdomain (recommended for enterprise or long-term testing).
- DNS + Port Forwarding: You can map a domain to your public IP with port forwarding.

---

## 🛠️ Troubleshooting
### Can't Log In to the Discovery Service After OAuth2 Setup?
If you’ve configured OAuth2 authentication in the Admin service and the Discovery UI doesn't log you in properly, the issue may be due to service-level cache or uninitialized internal state.

✅ Solution: Restart all services to ensure everything is in sync:

```bash
docker compose down
docker compose up -d
```
This typically resolves login-related issues after OAuth2 configuration changes. If the problem persists, verify that:
- Environment variables in .env.discovery are correctly set (CLIENT_ID, TENANT_ID, CLIENT_SECRET)
- The OAuth2 provider callback URL matches the public URL used during setup

## Adding Trusted TLS Certificates
If your application needs to call a service that uses a private or self-signed certificate, follow these steps to trust its .cer file:
1. Create a certs/ folder at the project root (next to your docker-compose.yml).
2. Copy each .cer file (e.g. ecm.cer) into certs/.
3. Mount the folder in your service definition:
```yaml
services:
  threesixty-admin:
    
    volumes:
      - ./certs:/opt/certs:ro
```
4. On container start, docker-entrypoint.sh will detect `/opt/certs/*.cer` and import them into the JVM’s default truststore using keytool -cacerts.

**When to add new certificates**
- Whenever you onboard or rotate a downstream service certificate that isn’t signed by a public CA.
- After placing new .cer files in certs/, simply redeploy the container to apply the change.
