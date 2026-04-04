#!/bin/bash

set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
COMPOSE_FILE="docker-compose.devops.yml"
PIPELINE_REPO_URL="https://github.com/Benjaminnnnnn/spring-petclinic.git"
PIPELINE_REPO_BRANCH="main"

default_sonar_host() {
    local sonar_scheme="http"

    if [ -f "/.dockerenv" ]; then
        if command -v getent >/dev/null 2>&1 && getent hosts host.docker.internal >/dev/null 2>&1; then
            printf '%s://%s' "$sonar_scheme" "host.docker.internal:9000"
            return 0
        fi
    fi

    printf '%s://%s' "$sonar_scheme" "localhost:9000"
}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    cat <<EOF
Usage: ./setup.sh [--branch <branch>]

Defaults:
  repo        https://github.com/Benjaminnnnnn/spring-petclinic.git
  --branch    main
EOF
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --branch)
                shift
                [ "$#" -gt 0 ] || { echo "Missing value for --branch" >&2; exit 1; }
                PIPELINE_REPO_BRANCH="$1"
                ;;
            --branch=*)
                PIPELINE_REPO_BRANCH="${1#*=}"
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown argument: $1" >&2
                usage >&2
                exit 1
                ;;
        esac
        shift
    done
}

parse_args "$@"

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

detect_vagrant_ssh_value() {
    local key="$1"
    local ssh_config

    if [ ! -f "Vagrantfile" ] || ! command -v vagrant >/dev/null 2>&1; then
        return 1
    fi

    ssh_config="$(vagrant ssh-config 2>/dev/null || true)"
    if [ -z "$ssh_config" ]; then
        return 1
    fi

    awk -v wanted_key="$key" '$1 == wanted_key { print $2; exit }' <<< "$ssh_config"
}

detect_vagrant_forwarded_port() {
    local guest_port="$1"
    local forwarded_port

    if [ ! -f "Vagrantfile" ] || ! command -v vagrant >/dev/null 2>&1; then
        return 1
    fi

    forwarded_port="$(
        vagrant port 2>/dev/null | awk -v guest_port="$guest_port" '
            $1 == guest_port && $2 == "(guest)" && $4 == "(host)" { print $3; exit }
        '
    )"

    if [ -n "$forwarded_port" ]; then
        printf '%s' "$forwarded_port"
        return 0
    fi

    return 1
}

detect_vagrant_vm_host() {
    local detected_host

    detected_host="$(detect_vagrant_ssh_value "HostName" 2>/dev/null || true)"
    if [ -n "$detected_host" ]; then
        printf '%s' "$detected_host"
        return 0
    fi

    return 1
}

detect_vagrant_vm_ssh_port() {
    local detected_port

    detected_port="$(detect_vagrant_ssh_value "Port" 2>/dev/null || true)"
    if [ -n "$detected_port" ]; then
        printf '%s' "$detected_port"
        return 0
    fi

    return 1
}

detect_vagrant_vm_app_port() {
    local detected_host
    local forwarded_port

    detected_host="$(detect_vagrant_vm_host 2>/dev/null || true)"
    forwarded_port="$(detect_vagrant_forwarded_port "8080" 2>/dev/null || true)"

    if [ -n "$forwarded_port" ]; then
        printf '%s' "$forwarded_port"
        return 0
    fi

    if [ -n "$detected_host" ]; then
        printf '%s' "8080"
        return 0
    fi

    return 1
}

resolve_deploy_target_value() {
    local key="$1"
    local fallback_default="$2"
    local detected_value=""

    case "$key" in
        PRODUCTION_VM_HOST)
            detected_value="$(detect_vagrant_vm_host 2>/dev/null || true)"
            ;;
        PRODUCTION_VM_SSH_PORT)
            detected_value="$(detect_vagrant_vm_ssh_port 2>/dev/null || true)"
            ;;
        PRODUCTION_VM_APP_PORT)
            detected_value="$(detect_vagrant_vm_app_port 2>/dev/null || true)"
            ;;
    esac

    if [ -n "$detected_value" ]; then
        resolve_env_value "$key" "$detected_value"
    else
        resolve_env_value "$key" "$fallback_default"
    fi
}

GRAFANA_HOST_PORT="$(resolve_env_value "GRAFANA_HOST_PORT" "3030")"
PRODUCTION_VM_HOST="$(resolve_deploy_target_value "PRODUCTION_VM_HOST" "host.docker.internal")"
PRODUCTION_VM_USER="$(resolve_env_value "PRODUCTION_VM_USER" "deployer")"
PRODUCTION_VM_SSH_PORT="$(resolve_deploy_target_value "PRODUCTION_VM_SSH_PORT" "2222")"
PRODUCTION_VM_APP_PORT="$(resolve_deploy_target_value "PRODUCTION_VM_APP_PORT" "8080")"
SONAR_ADMIN_USER="$(resolve_env_value "SONAR_ADMIN_USER" "admin")"
SONAR_ADMIN_PASSWORD="$(resolve_env_value "SONAR_ADMIN_PASSWORD" "admin")"
SONAR_HOST="$(resolve_env_value "SONAR_HOST" "$(default_sonar_host)")"

upsert_env_value "GRAFANA_HOST_PORT" "$GRAFANA_HOST_PORT"
upsert_env_value "PIPELINE_REPO_URL" "$PIPELINE_REPO_URL"
upsert_env_value "PIPELINE_REPO_BRANCH" "$PIPELINE_REPO_BRANCH"
upsert_env_value "PRODUCTION_VM_HOST" "$PRODUCTION_VM_HOST"
upsert_env_value "PRODUCTION_VM_USER" "$PRODUCTION_VM_USER"
upsert_env_value "PRODUCTION_VM_SSH_PORT" "$PRODUCTION_VM_SSH_PORT"
upsert_env_value "PRODUCTION_VM_APP_PORT" "$PRODUCTION_VM_APP_PORT"
upsert_env_value "SONAR_HOST" "$SONAR_HOST"

echo "=========================================="
echo "Pulling Docker Images"
echo "=========================================="
echo ""

export DOCKER_CLIENT_TIMEOUT=600
export COMPOSE_HTTP_TIMEOUT=600

images=(
    "postgres:15-alpine"
    "postgres:18.3"
    "mysql:9.6"
    "prom/prometheus:latest"
    "grafana/grafana:latest"
    "jenkins/jenkins:lts-jdk17"
    "sonarqube:lts-community"
    "zaproxy/zap-stable"
)

for image in "${images[@]}"; do
    echo "Pulling ${image}..."
    docker pull "${image}"
done

echo ""
echo "=========================================="
echo "Starting DevOps Services"
echo "=========================================="
echo ""

echo "Starting SonarQube, monitoring, and DAST services..."
docker compose -f "$COMPOSE_FILE" up -d --remove-orphans postgresql sonarqube prometheus grafana burpsuite

echo ""
echo "Bootstrapping SonarQube token..."
if GENERATED_SONAR_TOKEN="$(SONAR_HOST="$SONAR_HOST" SONAR_ADMIN_USER="$SONAR_ADMIN_USER" SONAR_ADMIN_PASSWORD="$SONAR_ADMIN_PASSWORD" ./scripts/bootstrap-sonarqube.sh 2>/dev/null)"; then
    echo -e "${GREEN}✓ SonarQube token ready and persisted in ${ENV_FILE}${NC}"
else
    echo -e "${RED}✗ SonarQube token bootstrap failed.${NC}"
    exit 1
fi

echo ""
echo "Starting Jenkins with the current SonarQube token..."
docker compose -f "$COMPOSE_FILE" up -d --build --force-recreate --remove-orphans jenkins

echo ""
echo "=========================================="
echo "Services Started!"
echo "=========================================="
echo ""
echo "Pipeline repository:"
echo "  ${PIPELINE_REPO_URL}"
echo "Pipeline branch:"
echo "  ${PIPELINE_REPO_BRANCH}"
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
echo "Check status with:"
echo "  docker compose -f ${COMPOSE_FILE} ps"
echo ""
echo "View logs with:"
echo "  docker compose -f ${COMPOSE_FILE} logs -f [service-name]"
echo ""
