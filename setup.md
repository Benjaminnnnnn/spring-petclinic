# Spring PetClinic DevSecOps Pipeline — Setup Guide

This guide walks you through the complete setup from a fresh machine to a running CI/CD pipeline with automated deployment. Follow the steps in order.

---

## Overview

The setup uses **two separate environments** that must not be swapped:

| Environment | Purpose | Where to run it |
|---|---|---|
| **Host machine** | Runs the production VM | Your laptop/desktop |
| **Dev container** | Runs the DevOps stack (Jenkins, SonarQube, etc.) | Inside VS Code |

The production application (Spring PetClinic) is **not** deployed into Docker containers. Jenkins builds it and deploys it to the Vagrant VM using Ansible.

### What Gets Started

After setup, you will have:

- **Production VM** (Vagrant): the target environment where the app runs
- **Jenkins** (`localhost:8081`): builds, tests, and deploys the app
- **SonarQube** (`localhost:9000`): static code analysis and quality gate
- **Prometheus** (`localhost:9090`): metrics collection
- **Grafana** (`localhost:3030`): metrics dashboard
- **OWASP ZAP** (`localhost:8090`): dynamic application security testing
- **Spring PetClinic app** (`localhost:8080`): deployed by Jenkins to the VM

---

## Step 1: Install Prerequisites

Starting assumption: **Docker Desktop is already installed and running.**

You still need to install the following tools on your host machine.

### Required for everyone

| Tool | Purpose | Install |
|---|---|---|
| Git | Clone the repository | [git-scm.com](https://git-scm.com) or `brew install git` |
| VS Code | Open the dev container | [code.visualstudio.com](https://code.visualstudio.com) |
| VS Code Dev Containers extension | Run the dev container | Install from VS Code Extensions panel (`ms-vscode-remote.remote-containers`) |
| Vagrant | Manage the production VM | See below |
| VM provider | Runs the Vagrant VM | See below — depends on your CPU |

### Install Vagrant and a VM provider

**Intel / AMD Mac or Linux:**

```bash
brew install --cask vagrant
brew install --cask virtualbox
```

**Apple Silicon Mac (M1/M2/M3):**

VirtualBox does not support Apple Silicon. Use VMware Fusion instead.

1. Download and install [VMware Fusion](https://www.vmware.com/products/fusion.html) (free for personal use)
2. Download and install the [Vagrant VMware Utility](https://developer.hashicorp.com/vagrant/docs/providers/vmware/vagrant-vmware-utility)
3. Install the Vagrant VMware plugin:

```bash
brew install --cask vagrant
vagrant plugin install vagrant-vmware-desktop
```

### Verify your installs

```bash
git --version
vagrant --version
docker --version
```

All three commands should print a version number before continuing.

---

## Step 2: Clone the Repository

Run this on the host machine:

```bash
git clone https://github.com/Benjaminnnnnn/spring-petclinic.git
cd spring-petclinic
```

If you are working on a specific branch, check it out now:

```bash
git checkout <your-branch>
```

---

## Step 3: Start the Production VM

Run this on the **host machine** from the repository root:

```bash
vagrant up
```

This will take a few minutes on first run. It will:

1. Download the Ubuntu VM image (only on first run)
2. Create and boot the VM
3. Install Python 3, Java 17, and SSH server inside the VM
4. Create a `deployer` user with SSH access
5. Generate a Jenkins deploy key under `.jenkins-ssh/`
6. Install the deploy key on the VM for the `deployer` user
7. Write deployment connection values into `.env`

### Verify the VM is ready

```bash
vagrant status
vagrant ssh -c "hostname && python3 --version && java -version"
```

Expected output:
- VM status is `running`
- Python 3 is present
- Java 17 is present

Also confirm `.env` was written with deployment values:

```bash
cat .env
```

You should see `PRODUCTION_VM_HOST`, `PRODUCTION_VM_USER`, `PRODUCTION_VM_SSH_PORT`, and `PRODUCTION_VM_APP_PORT`.

---

## Step 4: Open the Dev Container

1. Open VS Code
2. Open the `spring-petclinic` folder (`File → Open Folder`)
3. VS Code will detect `.devcontainer/devcontainer.json` and show a prompt — click **Reopen in Container**

   If you do not see the prompt: open the Command Palette (`Cmd+Shift+P` / `Ctrl+Shift+P`) and run **Dev Containers: Reopen in Container**

4. Wait for the container to build and start (first time takes a few minutes)
5. Open a new terminal inside VS Code — it will be inside the dev container

> All remaining steps must be run in this dev container terminal, not in a host terminal.

---

## Step 5: Start the DevOps Stack

Inside the dev container terminal:

```bash
./setup.sh
```

This single command does everything:

1. Pulls all required Docker images (Jenkins, SonarQube, PostgreSQL, Prometheus, Grafana, OWASP ZAP)
2. Starts PostgreSQL and SonarQube, waits for them to be healthy
3. Generates a SonarQube token for Jenkins
4. Starts Jenkins with the pipeline job pre-configured via JCasC
5. Triggers the first pipeline build automatically
6. Writes all effective values to `.env`

This will take **5–10 minutes** on first run due to image pulls and SonarQube startup time.

### Optional: use a specific branch

By default, Jenkins pulls from the `main` branch. To use a different branch:

```bash
./setup.sh --branch feat/your-feature-branch
```

---

## Step 6: Verify the Services

After `./setup.sh` finishes, open these URLs **in a browser on your host machine**:

| Service | URL | Default login |
|---|---|---|
| Jenkins | `http://localhost:8081` | `admin` / `admin` |
| SonarQube | `http://localhost:9000` | `admin` / `admin` |
| Prometheus | `http://localhost:9090` | — |
| Grafana | `http://localhost:3030` | `admin` / `admin` |
| OWASP ZAP | `http://localhost:8090` | — |

In Jenkins, you should see:

- Jenkins is initialized (no setup wizard)
- A pipeline job named `spring-petclinic-pipeline` already exists
- SonarQube is pre-configured
- A build is already running or queued (triggered automatically by `setup.sh`)

---

## Step 7: Wait for the First Pipeline Build

The first build will:

1. Check out the repository from GitHub
2. Build the Spring Boot JAR
3. Run unit tests and generate JaCoCo coverage
4. Run SonarQube static analysis
5. Wait for the SonarQube quality gate
6. Build a Docker image
7. Run OWASP ZAP security scan
8. Deploy the JAR to the Vagrant VM via Ansible
9. Verify the deployed application is healthy

The first build takes **10–15 minutes**.

Watch it in Jenkins at `http://localhost:8081`.

---

## Step 8: Verify the Deployed Application

After the pipeline build succeeds, open the production app on your host machine:

```
http://localhost:8080
```

You should see the Spring PetClinic welcome page.

You can also verify directly from the host:

```bash
vagrant ssh -c "curl -fsS http://localhost:8080/actuator/health && echo"
```

Expected response contains `"status":"UP"`.

---

## Step 9: Verify Automatic CI/CD (Optional)

To confirm the full CI/CD loop works:

1. Make any visible code change (e.g., edit the welcome page title)
2. Commit and push to your branch
3. Jenkins polls SCM every 5 minutes — it will detect the push and start a new build automatically
4. After the build succeeds, reload `http://localhost:8080` to see the change live

---

## Stopping and Resetting

### Stop the DevOps stack (keep data)

Inside the dev container:

```bash
docker compose -f docker-compose.devops.yml down
```

Restart it later with `./setup.sh`.

### Full reset (wipe all data)

Inside the dev container:

```bash
docker compose -f docker-compose.devops.yml down -v
./setup.sh
```

### Destroy and recreate the VM

On the host machine:

```bash
vagrant destroy -f
vagrant up
```

Then run `./setup.sh` again inside the dev container.

---

## Troubleshooting

### VM fails to start on Apple Silicon

Make sure VMware Fusion, the Vagrant VMware Utility, and the `vagrant-vmware-desktop` plugin are all installed. The plugin version must be compatible with your Vagrant version — run `vagrant plugin update vagrant-vmware-desktop` if unsure.

### `./setup.sh` fails with "SonarQube did not reach UP state"

SonarQube can be slow on first startup. Run `./setup.sh` again — it is safe to re-run.

### Jenkins build fails: tool "Maven" or "JDK17" not found

Jenkins was rebuilt without the tool configuration. Re-run:

```bash
docker compose -f docker-compose.devops.yml up -d --build --force-recreate jenkins
```

### Jenkins build fails: `http://` URL in Jenkinsfile fails checkstyle

The `nohttp` checkstyle rule rejects literal `http://` URLs in source files. The local Jenkinsfile already uses the `printf` workaround to avoid this. Make sure the branch Jenkins is building has the latest Jenkinsfile. If Jenkins is still targeting `main` and `main` is outdated, push your branch and run:

```bash
./setup.sh --branch your-branch
```

### App not reachable at `localhost:8080`

Check the VM is running and the pipeline has succeeded:

```bash
vagrant status
vagrant ssh -c "ss -tlnp | grep 8080"
```

If port 8080 is not listening, the app has not been deployed yet. Trigger a Jenkins build.

### `vagrant up` says port 2222 is already in use

Another VM is using the SSH forwarded port. Either stop it or set a different port:

```bash
VAGRANT_HOST_SSH_PORT=2223 vagrant up
```

---

## Quick Reference

**First-time setup — run these in order:**

```bash
# 1. Host machine
git clone https://github.com/Benjaminnnnnn/spring-petclinic.git
cd spring-petclinic
vagrant up

# 2. Open VS Code → Reopen in Container

# 3. Dev container terminal
./setup.sh
```

**Service URLs:**

| Service | URL |
|---|---|
| Spring PetClinic (app) | `http://localhost:8080` |
| Jenkins | `http://localhost:8081` |
| SonarQube | `http://localhost:9000` |
| Prometheus | `http://localhost:9090` |
| Grafana | `http://localhost:3030` |
| OWASP ZAP | `http://localhost:8090` |
