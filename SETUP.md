# Spring PetClinic DevOps Setup

This guide is the single setup document for this repository. Follow it from top to bottom on a clean machine and you should be able to bring up the full local CI/CD pipeline, run Jenkins, and deploy the application to the production VM.

The setup has two environments:

- **Host machine**: runs the production VM with Vagrant
- **Dev container**: runs the containerized DevOps stack with Docker

Do not swap them:

- run `vagrant` commands on the **host**
- run `./setup.sh` inside the **dev container**

## 1. What This Repository Starts

The local DevOps stack starts these services:

- Jenkins
- SonarQube
- Prometheus
- Grafana
- OWASP ZAP in the `burpsuite` service
- PostgreSQL for SonarQube

The production application itself is **not** deployed into those containers. Jenkins deploys the Spring PetClinic JAR to a separate Linux VM using Ansible.

## 2. Prerequisites

### Host Machine

Install:

- Docker Desktop
- Git
- VS Code
- VS Code Dev Containers extension
- Vagrant

Install one VM provider:

- Intel / AMD Mac:
  - VirtualBox
- Apple Silicon Mac:
  - VMware Fusion
  - Vagrant VMware Utility
  - `vagrant-vmware-desktop` plugin

Example install commands:

Intel / AMD host:

```bash
brew install --cask docker
brew install --cask vagrant
brew install --cask virtualbox
```

Apple Silicon host:

```bash
brew install --cask docker
brew install --cask vagrant
vagrant plugin install vagrant-vmware-desktop
```

Then install VMware Fusion and the Vagrant VMware Utility manually.

### Dev Container

You only need:

- Docker Desktop running on the host
- this repository opened in the VS Code dev container

## 3. Clone Your Fork

Fork the repository first, then clone your fork on the host:

```bash
git clone https://github.com/Benjaminnnnnn/spring-petclinic.git
cd spring-petclinic
```

If you are working on a branch other than `main`, create it now.

## 4. Host Setup: Start the Production VM

From the repository root on the host:

```bash
vagrant up
```

What this does:

- creates the Linux VM from [Vagrantfile](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/Vagrantfile)
- provisions the `deployer` user
- installs Python 3 and Java 17 in the VM
- exports deployment values into [`.env`](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/.env)
- generates a Jenkins deploy key under [`.jenkins-ssh/`](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/.jenkins-ssh)
- installs that key into the VM for the `deployer` user

The host-side automation is performed by:

- [Vagrantfile](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/Vagrantfile)
- [export-vagrant-env.sh](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/scripts/export-vagrant-env.sh)
- [bootstrap-vagrant-vm.sh](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/scripts/bootstrap-vagrant-vm.sh)

### Verify the VM

Run these on the host:

```bash
vagrant status
vagrant ssh -c "hostname && python3 --version && java -version"
```

You should see:

- VM status is `running`
- Python 3 is installed
- Java 17 is installed

You should also see deployment values in [`.env`](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/.env):

- `PRODUCTION_VM_HOST`
- `PRODUCTION_VM_USER`
- `PRODUCTION_VM_SSH_PORT`
- `PRODUCTION_VM_APP_PORT`

## 5. Open the Repository in the Dev Container

From VS Code on the host:

1. Open the repository folder
2. Reopen it in the dev container
3. Open a terminal inside the dev container

All remaining steps in this guide should be run inside that dev container terminal unless a step explicitly says otherwise.

## 6. Dev Container Setup: Start the DevOps Stack

Inside the dev container:

```bash
chmod 755 setup.sh stop-services.sh
export PIPELINE_REPO_URL="https://github.com/Benjaminnnnnn/spring-petclinic.git"
export PIPELINE_REPO_BRANCH="<your-branch>"
./setup.sh
```

If you want Jenkins to build the default branch, omit `PIPELINE_REPO_BRANCH`.

### What `./setup.sh` Does

[setup.sh](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/setup.sh) is the main automation script. It:

- pulls the required Docker images
- starts PostgreSQL, SonarQube, Prometheus, Grafana, and OWASP ZAP
- bootstraps a fresh SonarQube token for Jenkins
- starts Jenkins with JCasC and the pipeline job preconfigured
- persists effective values in [`.env`](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/.env)

## 7. Service URLs

After `./setup.sh` finishes, open these on the **host machine**:

- Jenkins: `http://localhost:8081`
- SonarQube: `http://localhost:9000`
- Prometheus: `http://localhost:9090`
- Grafana: `http://localhost:3030`
- OWASP ZAP API: `http://localhost:8090`

The deployed production application should be reachable on the host at:

- `http://localhost:8080`

If your Vagrant/provider combination exports a guest IP instead of relying on forwarded host ports, use the values in [`.env`](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/.env), especially:

- `PRODUCTION_VM_HOST`
- `PRODUCTION_VM_APP_PORT`

## 8. Default Credentials

- Jenkins: `admin / admin`
- SonarQube: `admin / admin` on a fresh stack
- Grafana: `admin / admin`

## 9. Verify Jenkins Auto-Configuration

Open Jenkins at `http://localhost:8081`.

You should see:

- Jenkins is already initialized
- a pipeline job named `spring-petclinic-pipeline`
- SonarQube configured through JCasC
- Prometheus metrics enabled for Jenkins

The auto-configured Jenkins job comes from [jenkins-config/casc.yaml](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/jenkins-config/casc.yaml).

## 10. Run the Pipeline

In Jenkins:

1. Open `spring-petclinic-pipeline`
2. Trigger a build

The pipeline should:

- checkout the repository from your fork
- build the Spring Boot project
- run unit and integration tests
- publish JaCoCo test results
- run SonarQube analysis
- build the Docker image
- run Dynamic Application Security Testing
- deploy the application to the VM with Ansible
- verify the deployed application health and homepage

## 11. Verify Deployment

After the pipeline succeeds, open the production app from the host:

```text
http://localhost:8080
```

You should see the Spring PetClinic welcome page.

You can also verify from the VM directly on the host:

```bash
vagrant ssh -c "curl -fsS http://localhost:8080/actuator/health && echo"
```

## 12. Verify Automatic Rebuild and Redeploy

To prove the CI/CD flow works:

1. Make a visible code change in your branch
2. Commit and push it to your fork
3. Wait for Jenkins SCM polling to detect it
4. Verify Jenkins starts a new pipeline run automatically
5. Verify the deployed application updates on the VM

The SCM polling trigger is configured in [jenkins-config/casc.yaml](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/jenkins-config/casc.yaml).

## 13. Stop or Reset the Stack

Inside the dev container:

Stop containers but keep data:

```bash
./stop-services.sh
```

Equivalent command:

```bash
docker compose -f docker-compose.devops.yml down
```

Reset the Docker-based DevOps stack completely:

```bash
docker compose -f docker-compose.devops.yml down -v
```

Then rerun:

```bash
./setup.sh
```

If you also want to recreate the VM, do that on the host:

```bash
vagrant destroy -f
vagrant up
```

## 14. Common Mistakes

- Running `./setup.sh` on the host instead of in the dev container
- Running `vagrant up` in the dev container instead of on the host
- Using a stale SonarQube or Jenkins volume from an older environment
- Forgetting to set `PIPELINE_REPO_URL` to your fork before starting Jenkins
- Verifying the deployed app inside the Docker stack instead of on the VM

## 15. Quick Start Summary

On the host:

```bash
git clone https://github.com/Benjaminnnnnn/spring-petclinic.git
cd spring-petclinic
vagrant up
```

In the dev container:

```bash
export PIPELINE_REPO_URL="https://github.com/Benjaminnnnnn/spring-petclinic.git"
export PIPELINE_REPO_BRANCH="<your-branch>"
./setup.sh
```

Then open:

- Jenkins: `http://localhost:8081`
- SonarQube: `http://localhost:9000`
- Grafana: `http://localhost:3030`
- Prometheus: `http://localhost:9090`
- Deployed app: `http://localhost:8080`
