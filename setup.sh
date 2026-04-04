#!/bin/bash

# Script to pre-download all Docker images
# This helps avoid timeout issues during docker-compose up

set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
COMPOSE_FILE="docker-compose.devops.yml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

read_env_value() {
    local key="$1"

    if [ ! -f "$ENV_FILE" ]; then
        return 1
    fi

    awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1) }' "$ENV_FILE" | tail -n 1
}

upsert_env_value() {
    local key="$1"
    local value="$2"
    local tmp_file

    tmp_file="$(mktemp)"
    touch "$ENV_FILE"

    awk -F= -v key="$key" -v value="$value" '
        BEGIN { updated = 0 }
        $1 == key {
            print key "=" value
            updated = 1
            next
        }
        { print }
        END {
            if (!updated) {
                print key "=" value
            }
        }
    ' "$ENV_FILE" > "$tmp_file"

    mv "$tmp_file" "$ENV_FILE"
}

resolve_env_value() {
    local key="$1"
    local default_value="$2"
    local shell_value="${!key-}"
    local file_value=""

    file_value="$(read_env_value "$key" 2>/dev/null || true)"

    if [ -n "$shell_value" ]; then
        printf '%s' "$shell_value"
    elif [ -n "$file_value" ]; then
        printf '%s' "$file_value"
    else
        printf '%s' "$default_value"
    fi
}

GRAFANA_HOST_PORT="$(resolve_env_value "GRAFANA_HOST_PORT" "3030")"
PIPELINE_REPO_URL="$(resolve_env_value "PIPELINE_REPO_URL" "https://github.com/Benjaminnnnnn/spring-petclinic.git")"
PIPELINE_REPO_BRANCH="$(resolve_env_value "PIPELINE_REPO_BRANCH" "main")"
PRODUCTION_VM_HOST="$(resolve_env_value "PRODUCTION_VM_HOST" "host.docker.internal")"
PRODUCTION_VM_USER="$(resolve_env_value "PRODUCTION_VM_USER" "deployer")"
PRODUCTION_VM_SSH_PORT="$(resolve_env_value "PRODUCTION_VM_SSH_PORT" "2222")"
PRODUCTION_VM_APP_PORT="$(resolve_env_value "PRODUCTION_VM_APP_PORT" "8080")"
SONARQUBE_TOKEN="$(resolve_env_value "SONARQUBE_TOKEN" "admin")"

upsert_env_value "GRAFANA_HOST_PORT" "$GRAFANA_HOST_PORT"
upsert_env_value "PIPELINE_REPO_URL" "$PIPELINE_REPO_URL"
upsert_env_value "PIPELINE_REPO_BRANCH" "$PIPELINE_REPO_BRANCH"
upsert_env_value "PRODUCTION_VM_HOST" "$PRODUCTION_VM_HOST"
upsert_env_value "PRODUCTION_VM_USER" "$PRODUCTION_VM_USER"
upsert_env_value "PRODUCTION_VM_SSH_PORT" "$PRODUCTION_VM_SSH_PORT"
upsert_env_value "PRODUCTION_VM_APP_PORT" "$PRODUCTION_VM_APP_PORT"
upsert_env_value "SONARQUBE_TOKEN" "$SONARQUBE_TOKEN"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Pulling Docker Images for DevOps${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Set longer timeout
export DOCKER_CLIENT_TIMEOUT=600
export COMPOSE_HTTP_TIMEOUT=600

# Define images
declare -a images=(
    "postgres:15-alpine|PostgreSQL|Small"
    "postgres:18.3|PostgreSQL Test DB|Large"
    "mysql:9.6|MySQL Test DB|Large"
    "prom/prometheus:latest|Prometheus|Medium"
    "grafana/grafana:latest|Grafana|Medium"
    "jenkins/jenkins:lts-jdk17|Jenkins|Large"
    "sonarqube:lts-community|SonarQube|Large"
    "zaproxy/zap-stable|OWASP ZAP|Large"
)

total_images=${#images[@]}
current_image=0

for img_info in "${images[@]}"; do
    IFS='|' read -r image name size <<< "$img_info"
    current_image=$((current_image + 1))
    
    echo -e "${YELLOW}[$current_image/$total_images] Pulling $name ($size)...${NC}"
    echo -e "${CYAN}Image: $image${NC}"
    
    max_retries=3
    retry_count=0
    success=false
    
    while [ "$success" = false ] && [ $retry_count -lt $max_retries ]; do
        if docker pull "$image"; then
            success=true
            echo -e "${GREEN}✓ $name downloaded successfully${NC}"
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                echo -e "${YELLOW}⚠ Retry $retry_count/$max_retries for $name...${NC}"
                sleep 5
            else
                echo -e "${RED}✗ Failed to download $name after $max_retries attempts${NC}"
            fi
        fi
    done
    
    echo ""
done

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Image Download Summary${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

echo -e "${YELLOW}Verifying downloaded images...${NC}"
echo ""

for img_info in "${images[@]}"; do
    IFS='|' read -r image name size <<< "$img_info"
    
    if docker images "$image" -q | grep -q .; then
        echo -e "${GREEN}✓ $name: Available${NC}"
    else
        echo -e "${RED}✗ $name: Missing${NC}"
    fi
done

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Next Steps:${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "${GREEN}All images downloaded! Now run:${NC}"
echo -e "${NC}  docker compose -f ${COMPOSE_FILE} up -d${NC}"
echo ""
echo -e "${GREEN}Or rerun this setup helper:${NC}"
echo -e "${NC}  ./setup.sh${NC}"
echo ""


echo "=========================================="
echo "Starting DevOps Services"
echo "=========================================="
echo ""

# Start all services
echo "Starting SonarQube, monitoring, and DAST services..."
docker compose -f "$COMPOSE_FILE" up -d postgresql sonarqube prometheus grafana burpsuite

echo ""
echo "Bootstrapping SonarQube token..."
if GENERATED_SONAR_TOKEN="$(./scripts/bootstrap-sonarqube.sh 2>/dev/null)"; then
    SONARQUBE_TOKEN="$GENERATED_SONAR_TOKEN"
    echo -e "${GREEN}✓ SonarQube token ready and persisted in ${ENV_FILE}${NC}"
else
    echo -e "${YELLOW}⚠ SonarQube token bootstrap failed. Jenkins will start with the current ${ENV_FILE} token value.${NC}"
    echo -e "${YELLOW}  If this is a reused SonarQube volume with a changed admin password, set SONARQUBE_TOKEN manually and rerun setup.${NC}"
fi

echo ""
echo "Starting Jenkins with the current SonarQube token..."
docker compose -f "$COMPOSE_FILE" up -d --build --force-recreate jenkins

echo ""
echo "=========================================="
echo "Services Started!"
echo "=========================================="
echo ""
echo "Access your services at:"
echo "  Jenkins:    http://localhost:8081"
echo "  SonarQube:  http://localhost:9000 (admin/admin on a fresh volume)"
echo "  Prometheus: http://localhost:9090"
echo "  Grafana:    http://localhost:${GRAFANA_HOST_PORT} (admin/admin)"
echo "  OWASP ZAP:  http://localhost:8090"
echo ""
echo "Persisted local Compose settings:"
echo "  ${ENV_FILE}"
echo ""
echo "If SonarQube rejects admin/admin, reset persisted state with:"
echo "  docker compose -f ${COMPOSE_FILE} down -v"
echo "then rerun:"
echo "  ./setup.sh"
echo ""
echo "Check status with:"
echo "  docker compose -f ${COMPOSE_FILE} ps"
echo ""
echo "View logs with:"
echo "  docker compose -f ${COMPOSE_FILE} logs -f [service-name]"
echo ""
