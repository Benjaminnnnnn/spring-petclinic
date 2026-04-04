#!/bin/bash

set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
SONAR_HOST="${SONAR_HOST:-http://localhost:9000}"
SONAR_ADMIN_USER="${SONAR_ADMIN_USER:-admin}"
SONAR_ADMIN_PASSWORD="${SONAR_ADMIN_PASSWORD:-admin}"
SONAR_PROJECT_KEY="${SONAR_PROJECT_KEY:-spring-petclinic}"
SONAR_PROJECT_NAME="${SONAR_PROJECT_NAME:-spring-petclinic}"
TOKEN_PREFIX="${SONAR_TOKEN_PREFIX:-jenkins-token}"
SONAR_WEBHOOK_NAME="${SONAR_WEBHOOK_NAME:-jenkins-quality-gate}"
JENKINS_WEBHOOK_URL="${JENKINS_WEBHOOK_URL:-http://jenkins:8080/sonarqube-webhook/}"

read_env_value() {
    local key="$1"
    local file="${2:-$ENV_FILE}"

    if [ ! -f "$file" ]; then
        return 1
    fi

    awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1) }' "$file" | tail -n 1
}

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

token_is_valid() {
    local token="$1"
    local response

    if [ -z "$token" ]; then
        return 1
    fi

    response="$(
        curl -fsS -u "${token}:" \
            "$SONAR_HOST/api/authentication/validate" 2>/dev/null || true
    )"

    printf '%s' "$response" | grep -q '"valid":true'
}

generate_token() {
    local token_name="${TOKEN_PREFIX}-$(date +%s)"
    local response

    response="$(
        curl -fsS -u "${SONAR_ADMIN_USER}:${SONAR_ADMIN_PASSWORD}" \
            -X POST "$SONAR_HOST/api/user_tokens/generate" \
            --data-urlencode "name=${token_name}" 2>/dev/null || true
    )"

    printf '%s' "$response" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p'
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
    local existing_token
    local token

    if ! wait_for_sonarqube; then
        echo "SonarQube did not reach UP state in time." >&2
        exit 1
    fi

    existing_token="$(read_env_value "SONARQUBE_TOKEN" 2>/dev/null || true)"
    if [ -n "$existing_token" ] && [ "$existing_token" != "admin" ]; then
        if token_is_valid "$existing_token"; then
            create_project
            ensure_webhook
            printf '%s\n' "$existing_token"
            exit 0
        fi
    fi

    token="$(generate_token)"
    if [ -z "$token" ]; then
        echo "Failed to generate a SonarQube token with ${SONAR_ADMIN_USER}/${SONAR_ADMIN_PASSWORD}." >&2
        exit 1
    fi

    upsert_env_value "SONARQUBE_TOKEN" "$token"
    create_project
    ensure_webhook
    printf '%s\n' "$token"
}

main "$@"
