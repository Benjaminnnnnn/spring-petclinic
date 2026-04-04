#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y openssh-server python3 python3-apt openjdk-17-jre-headless curl ufw

if ! id -u deployer >/dev/null 2>&1; then
  useradd -m -s /bin/bash deployer
fi

usermod -aG sudo deployer
echo "deployer ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/99-deployer
chmod 440 /etc/sudoers.d/99-deployer

install -d -m 700 -o deployer -g deployer /home/deployer/.ssh
touch /home/deployer/.ssh/authorized_keys
chmod 600 /home/deployer/.ssh/authorized_keys
chown deployer:deployer /home/deployer/.ssh/authorized_keys

# Allow the default Vagrant insecure key so the deployer user is reachable
# immediately after `vagrant up`. Add the Jenkins public key later for CI use.
VAGRANT_INSECURE_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEArTV3By5bXm5g3YJ0A1qV7Y5pY88MtXgFp0cNT6a8Fue91bLbX6FVUFYttGKIwEreX15HwXEx/EY8onj17ChuZQvNLVTHXZnmSx5+1H4ad8w49AmwlLDbSv71Y+KvfI8Dh8Jo6CQOdht6v7qAbKLFXrrHW+hP88D6UiHvxCcX/oHpUg3D7w/HkfgYz1CMLRMNzSVskLFaPrEMHcKXqswNy+tPV/e0c+mk1U9MGaI8BsopZHYEGQGvXHl5abZEWSIk2s9InBezVPSv+Xsg6grkQHIiph0QGlpIvFbc6FF2EePXOVdjFAPDi0KpF0us9rbAiSlzZlZTa3YL6hFLaQ== vagrant insecure public key"

if ! grep -q "vagrant insecure public key" /home/deployer/.ssh/authorized_keys; then
  echo "$VAGRANT_INSECURE_KEY" >>/home/deployer/.ssh/authorized_keys
fi

chown deployer:deployer /home/deployer/.ssh/authorized_keys

if command -v ufw >/dev/null 2>&1; then
  ufw allow 22/tcp || true
  ufw allow 8080/tcp || true
fi

systemctl enable ssh || true
