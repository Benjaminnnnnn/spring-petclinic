# VM Setup Guide

This repo includes a minimal Vagrant-based Ubuntu VM that works with both x86_64 and ARM hosts. The guest is intentionally small and only installs what the Jenkins + Ansible deployment needs:

- a `deployer` SSH user
- `python3` and `python3-apt` for Ansible
- Java 17 runtime for the PetClinic JAR
- SSH exposed on host port `2222`
- the deployed app exposed on host port `8080`

## Recommended Path: Architecture-Aware Vagrant VM

The root [`Vagrantfile`](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/Vagrantfile) auto-selects defaults based on the host CPU:

- `x86_64` / `amd64`: `ubuntu/jammy64` on `virtualbox`
- `arm64` / `aarch64`: `bytesguy/ubuntu-server-22.04-arm64` on `vmware_desktop`

You can override either choice with environment variables if your local provider differs.

### 1. Install the Required Host Tools

Intel / AMD host:

```bash
brew install --cask vagrant virtualbox
```

Apple Silicon host:

```bash
brew install --cask vagrant vmware-fusion
vagrant plugin install vagrant-vmware-desktop
```

### 2. Start the VM

From the repo root, the default command is now enough for most cases:

```bash
vagrant up
```

If you want to be explicit or need to override the auto-detected provider:

```bash
# x86_64 / amd64
vagrant up --provider=virtualbox

# arm64 / Apple Silicon
VAGRANT_DEFAULT_PROVIDER=vmware_desktop \
VAGRANT_BOX=bytesguy/ubuntu-server-22.04-arm64 \
vagrant up --provider=vmware_desktop
```

### 3. Optional Size Tuning

The VM is small by default: `2` CPUs and `2048` MB RAM. Override those only if your build or provider needs more headroom:

```bash
VAGRANT_VM_CPUS=4 VAGRANT_VM_MEMORY=4096 vagrant up
```

Other useful overrides:

```bash
VAGRANT_HOST_SSH_PORT=2223 VAGRANT_HOST_APP_PORT=8081 vagrant up
VAGRANT_VM_IP=192.168.56.21 vagrant up
```

### 4. Verify Basic Access

From the host:

```bash
vagrant ssh -c "hostname && python3 --version && java -version"
```

### 5. Add Jenkins SSH Access

Generate or print the Jenkins container public key:

```bash
docker exec jenkins cat /var/jenkins_home/.ssh/id_rsa.pub
```

Ensure the deployer SSH directory exists:

```bash
vagrant ssh -c 'sudo install -d -m 700 -o deployer -g deployer /home/deployer/.ssh && sudo touch /home/deployer/.ssh/authorized_keys && sudo chmod 600 /home/deployer/.ssh/authorized_keys && sudo chown deployer:deployer /home/deployer/.ssh/authorized_keys'
```

Append the Jenkins public key:

```bash
vagrant ssh
sudo -u deployer bash -lc 'echo "<jenkins-public-key>" >> ~/.ssh/authorized_keys'
exit
```

### 6. Configure Jenkins for the Vagrant VM

Set these Jenkins environment variables:

- `PRODUCTION_VM_HOST=host.docker.internal`
- `PRODUCTION_VM_USER=deployer`
- `PRODUCTION_VM_SSH_PORT=2222`
- `PRODUCTION_VM_APP_PORT=8080`

If you overrode the forwarded ports, use those values instead.

This works because the VM forwards:

- host `2222` -> guest `22`
- host `8080` -> guest `8080`

and the Jenkins container can reach the host machine at `host.docker.internal`.

### 7. Validate the Deployment Target

Before running the pipeline:

```bash
docker exec jenkins ssh -o StrictHostKeyChecking=no -p 2222 deployer@host.docker.internal "hostname && python3 --version && java -version"
curl http://localhost:8080 || true
```

The first successful deployment will replace the empty `8080` response with the Spring PetClinic welcome page.

## Option B: Manual VM Setup

If you already have a Linux VM, prepare it with the same baseline:

### 1. Create the Deployment User

```bash
sudo useradd -m -s /bin/bash deployer
sudo usermod -aG sudo deployer
```

### 2. Install Base Packages

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-apt openjdk-17-jre-headless curl
```

### 3. Add Jenkins SSH Access

Generate or print the Jenkins container public key:

```bash
docker exec jenkins cat /var/jenkins_home/.ssh/id_rsa.pub
```

Copy that key into the VM:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "<jenkins-public-key>" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### 4. Open the Application Port

Allow inbound TCP `8080` from the machine running Jenkins and Prometheus.

### 5. Validate Access

From the host running Docker:

```bash
ssh deployer@<vm-ip> "hostname && python3 --version && java -version"
```

### 6. Update Jenkins

Set:

- `PRODUCTION_VM_HOST=<vm-ip>`
- `PRODUCTION_VM_USER=deployer`
- `PRODUCTION_VM_SSH_PORT=22`
- `PRODUCTION_VM_APP_PORT=8080`

Once those variables are set, the pipeline deployment stages will run.
