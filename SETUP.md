# DevOps Environment Setup

Quick-start guide to run the DevOps stack locally. For the full assignment workflow, see [DEVOPS-README.md](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/DEVOPS-README.md).

## Prerequisites

- Dev container is running
- Docker is available inside the dev container

## Setup Instructions

### 1. Make Scripts Executable (First Time Only)

If this is your first time running the scripts, make them executable:

```bash
chmod 755 setup.sh stop-services.sh
```

### 2. Start Services

Inside your dev container terminal, run:

```bash
export PIPELINE_REPO_URL="https://github.com/Benjaminnnnnn/spring-petclinic.git"
./setup.sh
```

This script will:
- Pull all required Docker images (Jenkins, SonarQube, Prometheus, Grafana, OWASP ZAP, PostgreSQL)
- Start all services using Docker Compose
- Display service URLs and credentials

**Note:** First run may take 5-10 minutes to download images.

### 3. Stop Services

To stop all services:

```bash
./stop-services.sh
```

Or manually:

```bash
docker compose -f docker-compose.devops.yml down
```

To stop and remove volumes (clean slate):

```bash
docker compose -f docker-compose.devops.yml down -v
```

### 4. Check Service Status

```bash
docker compose -f docker-compose.devops.yml ps
```

### 5. View Logs

```bash
# All services
docker compose -f docker-compose.devops.yml logs -f

# Specific service
docker compose -f docker-compose.devops.yml logs -f jenkins
```

## Service Access

All services are accessible from your **host machine** (Windows) at the following URLs:

| Service | URL | Credentials |
|---------|-----|-------------|
| **Jenkins** | http://localhost:8081 | Get initial password: `docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword` |
| **SonarQube** | http://localhost:9000 | Username: `admin`<br>Password: `admin` |
| **Prometheus** | http://localhost:9090 | No authentication |
| **Grafana** | http://localhost:3000 | Username: `admin`<br>Password: `admin` |
| **OWASP ZAP** | http://localhost:8090 | API Key: `burp-api-key` |
| **PostgreSQL** | localhost:5432 | Username: `sonar`<br>Password: `sonar`<br>Database: `sonarqube` |

## Port Mapping

| Service | Container Port | Host Port |
|---------|----------------|-----------|
| Jenkins | 8080 | 8081 |
| Jenkins Agent | 50000 | 50000 |
| SonarQube | 9000 | 9000 |
| Prometheus | 9090 | 9090 |
| Grafana | 3000 | 3000 |
| OWASP ZAP API | 8090 | 8090 |
| OWASP ZAP Proxy | 8080 | 8080 |
| PostgreSQL | 5432 | (internal only) |

## Troubleshooting

### Services won't start
```bash
# Check Docker is running
docker ps

# Check logs for errors
docker compose -f docker-compose.devops.yml logs
```

### Port conflicts
If you get port binding errors, make sure no other services are using ports 3000, 8080, 8081, 8090, 9000, or 9090 on your host machine.

### Reset everything
```bash
# Stop and remove all containers, networks, and volumes
docker compose -f docker-compose.devops.yml down -v

# Remove all images (optional)
docker rmi jenkins/jenkins:lts-jdk17 sonarqube:lts-community zaproxy/zap-stable prom/prometheus:latest grafana/grafana:latest postgres:15-alpine

# Start fresh
./setup.sh
```
