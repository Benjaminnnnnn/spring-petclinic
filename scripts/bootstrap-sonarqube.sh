#!/bin/bash

set -euo pipefail

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

ENV_FILE="${ENV_FILE:-.env}"
SONAR_HOST="${SONAR_HOST:-$(default_sonar_host)}"
SONAR_ADMIN_USER="${SONAR_ADMIN_USER:-admin}"
SONAR_ADMIN_PASSWORD="${SONAR_ADMIN_PASSWORD:-admin}"
SONAR_PROJECT_KEY="${SONAR_PROJECT_KEY:-spring-petclinic}"
SONAR_PROJECT_NAME="${SONAR_PROJECT_NAME:-spring-petclinic}"
SONAR_TOKEN_NAME="${SONAR_TOKEN_NAME:-jenkins-token}"
SONAR_WEBHOOK_NAME="${SONAR_WEBHOOK_NAME:-jenkins-quality-gate}"
JENKINS_WEBHOOK_URL="${JENKINS_WEBHOOK_URL:-http://jenkins:8080/sonarqube-webhook/}"

upsert_env_value() {
    local key="$1"
    local value="$2"
    local file="${3:-$ENV_FILE}"
    local tmp_file

    tmp_file="$(mktemp)"
    touch "$file"

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
    ' "$file" > "$tmp_file"

    mv "$tmp_file" "$file"
}

clear_env_value() {
    local key="$1"
    local file="${2:-$ENV_FILE}"

    upsert_env_value "$key" "" "$file"
}

wait_for_sonarqube() {
    local attempts="${1:-60}"
    local delay_seconds="${2:-5}"
    local status

    for ((attempt = 1; attempt <= attempts; attempt++)); do
        status="$(curl -fsS "$SONAR_HOST/api/system/status" 2>/dev/null || true)"
        if printf '%s' "$status" | grep -q '"status":"UP"'; then
            return 0
        fi
        sleep "$delay_seconds"
    done

    return 1
}

basic_auth_is_valid() {
    local response

    response="$(
        curl -fsS -u "${SONAR_ADMIN_USER}:${SONAR_ADMIN_PASSWORD}" \
            "$SONAR_HOST/api/authentication/validate" 2>/dev/null || true
    )"

    printf '%s' "$response" | grep -q '"valid":true'
}

generate_token() {
    local response

    response="$(
        curl -fsS -u "${SONAR_ADMIN_USER}:${SONAR_ADMIN_PASSWORD}" \
            -X POST "$SONAR_HOST/api/user_tokens/generate" \
            --data-urlencode "name=${SONAR_TOKEN_NAME}" 2>/dev/null || true
    )"

    printf '%s' "$response" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p'
}

revoke_token() {
    curl -fsS -u "${SONAR_ADMIN_USER}:${SONAR_ADMIN_PASSWORD}" \
        -X POST "$SONAR_HOST/api/user_tokens/revoke" \
        --data-urlencode "name=${SONAR_TOKEN_NAME}" >/dev/null 2>&1 || true
}

create_project() {
    curl -fsS -u "${SONAR_ADMIN_USER}:${SONAR_ADMIN_PASSWORD}" \
        -X POST "$SONAR_HOST/api/projects/create" \
        --data-urlencode "name=${SONAR_PROJECT_NAME}" \
        --data-urlencode "project=${SONAR_PROJECT_KEY}" >/dev/null 2>&1 || true
}

ensure_webhook() {
    local webhooks

    webhooks="$(
        curl -fsS -u "${SONAR_ADMIN_USER}:${SONAR_ADMIN_PASSWORD}" \
            "$SONAR_HOST/api/webhooks/list" 2>/dev/null || true
    )"

    if printf '%s' "$webhooks" | grep -Fq "\"name\":\"${SONAR_WEBHOOK_NAME}\""; then
        return 0
    fi

    curl -fsS -u "${SONAR_ADMIN_USER}:${SONAR_ADMIN_PASSWORD}" \
        -X POST "$SONAR_HOST/api/webhooks/create" \
        --data-urlencode "name=${SONAR_WEBHOOK_NAME}" \
        --data-urlencode "url=${JENKINS_WEBHOOK_URL}" >/dev/null
}

main() {
    local token

    if ! wait_for_sonarqube; then
        echo "SonarQube did not reach UP state in time." >&2
        exit 1
    fi

    clear_env_value "SONARQUBE_TOKEN"
    if ! basic_auth_is_valid; then
        echo "Failed to authenticate to SonarQube with ${SONAR_ADMIN_USER}/${SONAR_ADMIN_PASSWORD}." >&2
        exit 1
    fi

    revoke_token
    token="$(generate_token)"
    if [ -z "$token" ]; then
        echo "Failed to generate the SonarQube token with ${SONAR_ADMIN_USER}/${SONAR_ADMIN_PASSWORD}." >&2
        exit 1
    fi

    upsert_env_value "SONARQUBE_TOKEN" "$token"
    create_project
    ensure_webhook
    printf '%s\n' "$token"
}

main "$@"
