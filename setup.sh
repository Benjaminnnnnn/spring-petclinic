#!/bin/bash

# Script to pre-download all Docker images
# This helps avoid timeout issues during docker-compose up

set -e

GRAFANA_HOST_PORT="${GRAFANA_HOST_PORT:-3030}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

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
echo -e "${NC}  docker compose -f docker-compose.devops.yml up -d${NC}"
echo ""
echo -e "${GREEN}Or rerun this setup helper:${NC}"
echo -e "${NC}  ./setup.sh${NC}"
echo ""


echo "=========================================="
echo "Starting DevOps Services"
echo "=========================================="
echo ""

# Start all services
echo "Starting Docker Compose services..."
docker compose -f docker-compose.devops.yml up -d

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
echo "If SonarQube rejects admin/admin, reset persisted state with:"
echo "  docker compose -f docker-compose.devops.yml down -v"
echo "then rerun:"
echo "  ./setup.sh"
echo ""
echo "Check status with:"
echo "  docker compose -f docker-compose.devops.yml ps"
echo ""
echo "View logs with:"
echo "  docker compose -f docker-compose.devops.yml logs -f [service-name]"
echo ""
