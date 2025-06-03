# 3Sixty Local Development

This repository contains everything you need to run all 3Sixty services locally via Docker Compose.

---

## Prerequisites

- **Docker** ≥ 20.10
- **Docker Compose** ≥ 1.29

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
- Ollama + oi-rag (your RAG/agent service) on the `threesixty` network

After remote agent is configured (`.env.oi-agent`) start the OI Remote Agent:
```bash
docker compose -f docker-compose.oi-agent.yaml up -d
```

---

## Access URLs
| Service              | URL                                                                        |
|----------------------|----------------------------------------------------------------------------|
| Admin UI             | [https://localhost/3sixty-admin/](https://localhost/3sixty-admin/)         |
| Discovery UI         | [https://localhost/3sixty-discovery/](https://localhost/3sixty-discovery/) |
| SCIM API             | [https://localhost/scim/v2/](https://localhost/scim/v2/)                   |
| OpenSearch Dashboard | [http://localhost:15601](http://localhost:15601)                           |

Certificates are loaded from `./nginx/certs/tls.crt & ./nginx/certs/tls.key`
