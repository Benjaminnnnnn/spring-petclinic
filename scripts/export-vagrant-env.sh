#!/bin/bash

set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
DEFAULT_APP_PORT="${DEFAULT_APP_PORT:-8080}"
DEPLOY_USER="${DEPLOY_USER:-deployer}"
JENKINS_SSH_DIR="${JENKINS_SSH_DIR:-.jenkins-ssh}"
JENKINS_SSH_KEY_PATH="${JENKINS_SSH_KEY_PATH:-${JENKINS_SSH_DIR}/id_rsa}"
JENKINS_SSH_PUB_PATH="${JENKINS_SSH_PUB_PATH:-${JENKINS_SSH_DIR}/id_rsa.pub}"

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

ensure_jenkins_ssh_keypair() {
    mkdir -p "$JENKINS_SSH_DIR"
    chmod 700 "$JENKINS_SSH_DIR"

    if [ -f "$JENKINS_SSH_KEY_PATH" ] && [ -f "$JENKINS_SSH_PUB_PATH" ]; then
        return 0
    fi

    ssh-keygen -t rsa -b 4096 -N "" -f "$JENKINS_SSH_KEY_PATH" -C "jenkins-deploy-key" >/dev/null
}

install_jenkins_key_on_vm() {
    local public_key

    public_key="$(cat "$JENKINS_SSH_PUB_PATH")"

    vagrant ssh -c "sudo install -d -m 700 -o ${DEPLOY_USER} -g ${DEPLOY_USER} /home/${DEPLOY_USER}/.ssh && \
sudo touch /home/${DEPLOY_USER}/.ssh/authorized_keys && \
sudo chmod 600 /home/${DEPLOY_USER}/.ssh/authorized_keys && \
sudo chown ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.ssh/authorized_keys && \
sudo grep -Fqx '${public_key}' /home/${DEPLOY_USER}/.ssh/authorized_keys || \
sudo sh -c \"printf '%s\n' '${public_key}' >> /home/${DEPLOY_USER}/.ssh/authorized_keys\" && \
sudo chown ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.ssh/authorized_keys" >/dev/null
}

detect_vm_guest_ip() {
    local detected_ip

    detected_ip="$(
        vagrant ssh -c "ip -4 route get 1.1.1.1 | awk '{print \$7; exit}'" 2>/dev/null \
            | tr -d '\r' \
            | tail -n 1
    )"

    if [ -n "$detected_ip" ] && [[ "$detected_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf '%s' "$detected_ip"
        return 0
    fi

    return 1
}

ssh_config="$(vagrant ssh-config 2>/dev/null || true)"
if [ -z "$ssh_config" ]; then
    echo "Unable to read Vagrant SSH config. Is the VM running?" >&2
    exit 1
fi

raw_host="$(awk '$1 == "HostName" { print $2; exit }' <<< "$ssh_config")"
ssh_port="$(awk '$1 == "Port" { print $2; exit }' <<< "$ssh_config")"

if [ -z "$raw_host" ] || [ -z "$ssh_port" ]; then
    echo "Vagrant SSH config is missing HostName or Port." >&2
    exit 1
fi

guest_ip="$(detect_vm_guest_ip 2>/dev/null || true)"

if [ -n "$guest_ip" ]; then
    deploy_host="$guest_ip"
    ssh_port="22"
    app_port="$DEFAULT_APP_PORT"
else
    case "$raw_host" in
        127.0.0.1|localhost|::1)
            deploy_host="host.docker.internal"
            app_port="$(
                vagrant port 2>/dev/null | awk '
                    $1 == "8080" && $2 == "(guest)" && $4 == "(host)" { print $3; exit }
                '
            )"
            ;;
        *)
            deploy_host="$raw_host"
            app_port="$DEFAULT_APP_PORT"
            ;;
    esac
fi

if [ -z "${app_port:-}" ]; then
    app_port="$DEFAULT_APP_PORT"
fi

ensure_jenkins_ssh_keypair
install_jenkins_key_on_vm

upsert_env_value "PRODUCTION_VM_HOST" "$deploy_host"
upsert_env_value "PRODUCTION_VM_USER" "$DEPLOY_USER"
upsert_env_value "PRODUCTION_VM_SSH_PORT" "$ssh_port"
upsert_env_value "PRODUCTION_VM_APP_PORT" "$app_port"

echo "Updated ${ENV_FILE} with Vagrant deployment target:"
echo "  PRODUCTION_VM_HOST=${deploy_host}"
echo "  PRODUCTION_VM_USER=${DEPLOY_USER}"
echo "  PRODUCTION_VM_SSH_PORT=${ssh_port}"
echo "  PRODUCTION_VM_APP_PORT=${app_port}"
echo "  JENKINS_SSH_KEY_PATH=${JENKINS_SSH_KEY_PATH}"
