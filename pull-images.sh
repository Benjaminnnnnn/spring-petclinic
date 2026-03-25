#!/bin/bash

# Script to pre-download all Docker images
# This helps avoid timeout issues during docker-compose up

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Pulling Docker Images for DevSecOps${NC}"
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
echo -e "${NC}  docker compose -f docker-compose-devsecops.yml up -d${NC}"
echo ""
echo -e "${GREEN}Or use the setup script:${NC}"
echo -e "${NC}  ./setup-devsecops.sh${NC}"
echo ""
