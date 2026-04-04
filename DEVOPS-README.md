# DevOps Pipeline for Spring PetClinic

This project extends Spring PetClinic with a containerized DevOps toolchain:

- Jenkins for CI/CD orchestration
- SonarQube for static analysis
- Prometheus and Grafana for monitoring
- OWASP ZAP as the automation-friendly substitute for Burp Suite Community Edition
- Ansible for deployment to a production VM

## Why OWASP ZAP Instead of Burp Suite Community

`instruction.md` asks for Burp Suite Community Edition in Docker. Burp Community is not designed for reliable unattended, headless Docker execution. This repo keeps the assignment intent by running OWASP ZAP in a `burpsuite` service and publishing a Burp-compatible DAST HTML report from Jenkins.

## Project Structure

- [docker-compose.devops.yml](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/docker-compose.devops.yml): containerized CI, analysis, monitoring, and DAST stack
- [jenkins/Dockerfile](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/jenkins/Dockerfile): custom Jenkins image with required CLI tools
- [jenkins/plugins.txt](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/jenkins/plugins.txt): Jenkins plugins required by the pipeline
- [jenkins-config/casc.yaml](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/jenkins-config/casc.yaml): Jenkins Configuration as Code
- [Jenkinsfile](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/Jenkinsfile): CI/CD pipeline definition
- [ansible/deploy-playbook.yml](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/ansible/deploy-playbook.yml): production VM deployment
- [prometheus/prometheus.yml](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/prometheus/prometheus.yml): metrics scrape configuration
- [prometheus/targets/petclinic.json](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/prometheus/targets/petclinic.json): deployed app scrape target
- [burp/zap-api-scan.sh](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/burp/zap-api-scan.sh): DAST automation script
- [scripts/full-automation.sh](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/scripts/full-automation.sh): bonus automation helper

## Step-by-Step Setup

### 1. Prerequisites

- Docker Desktop or Docker Engine with Compose support
- Git
- Access to a Linux VM for production deployment
- A public GitHub fork of this repository

### 2. Set the Pipeline Repository URL

Jenkins creates the pipeline job automatically from JCasC. Point it at your fork before starting the stack:

```bash
export PIPELINE_REPO_URL="https://github.com/Benjaminnnnnn/spring-petclinic.git"
```

Optional if you want Jenkins to use a generated SonarQube token instead of `admin`:

```bash
export SONARQUBE_TOKEN="<your-sonarqube-token>"
```

To create the token in SonarQube:

1. Start the stack and open `http://localhost:9000`.
2. Sign in as `admin / admin` on a fresh volume.
3. Open the user avatar in the top-right, then go to `My Account` → `Security`.
4. Enter a token name such as `jenkins-token`, click `Generate`, and copy the token immediately.

You can also generate it by API after login works:

```bash
curl -u admin:admin -X POST "http://localhost:9000/api/user_tokens/generate?name=jenkins-token"
```

### 3. Start the Containerized Toolchain

```bash
chmod 755 setup.sh stop-services.sh
./setup.sh
```

This builds the custom Jenkins image, pulls the other images, and starts:

- Jenkins at `http://localhost:8081`
- SonarQube at `http://localhost:9000`
- Prometheus at `http://localhost:9090`
- Grafana at `http://localhost:3030`
- OWASP ZAP API at `http://localhost:8090`

### 4. Log In to the Services

- Jenkins: `admin / admin`
- SonarQube: `admin / admin` on a fresh volume
- Grafana: `admin / admin`

After first SonarQube login, create a user token and export it as `SONARQUBE_TOKEN` for repeatable Jenkins scans.

If SonarQube does not accept `admin / admin`, an old Docker volume is probably being reused. Reset the stack with:

```bash
docker compose -f docker-compose.devops.yml down -v
./setup.sh
```

### 5. Confirm Jenkins Auto-Configuration

Jenkins should come up with:

- the required plugins preinstalled
- SonarQube configured
- Prometheus metrics enabled at `/prometheus`
- a pipeline job named `spring-petclinic-pipeline`

If Jenkins was previously started with an old volume, remove the volume first so JCasC and plugin bootstrapping can run cleanly:

```bash
docker compose -f docker-compose.devops.yml down -v
./setup.sh
```

### 6. Prepare the Production VM

Follow [VM-SETUP-GUIDE.md](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/VM-SETUP-GUIDE.md).

At minimum you need:

- a reachable Linux VM
- SSH access for the Jenkins container
- Python 3 on the VM
- port `8080` open to the machine running the monitoring stack

For a minimal local production target, the repo now includes a root [`Vagrantfile`](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/Vagrantfile) that selects sensible defaults for both x86_64 and ARM hosts:

```bash
vagrant up
```

Use the Vagrant-backed Jenkins settings:

- `PRODUCTION_VM_HOST=host.docker.internal`
- `PRODUCTION_VM_USER=deployer`
- `PRODUCTION_VM_SSH_PORT=2222`
- `PRODUCTION_VM_APP_PORT=8080`

### 7. Configure Deployment Variables in Jenkins

These values are now injected into Jenkins automatically by Docker Compose and JCasC.

For the default Vagrant VM, no manual Jenkins UI setup is required.

If you need different values, export them before starting the stack:

```bash
export PRODUCTION_VM_HOST=host.docker.internal
export PRODUCTION_VM_USER=deployer
export PRODUCTION_VM_SSH_PORT=2222
export PRODUCTION_VM_APP_PORT=8080
./setup.sh
```

If Jenkins is already running, restart it after changing the variables:

```bash
docker compose -f docker-compose.devops.yml up -d --force-recreate jenkins
```

### 8. Point Prometheus at the Deployed VM

For the included Vagrant VM, you can keep [prometheus/targets/petclinic.json](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/prometheus/targets/petclinic.json) pointed at `host.docker.internal:8080`.

For a separate VM, replace `host.docker.internal:8080` with `<vm-ip>:8080`, then reload Prometheus:

```bash
docker compose -f docker-compose.devops.yml restart prometheus
```

### 9. Run the Pipeline

Trigger the Jenkins job once manually to confirm:

1. checkout works against your fork
2. Maven build and tests pass
3. SonarQube analysis appears in SonarQube
4. dependency scan report is published
5. DAST report is published
6. Ansible deploys to the VM
7. the deployed welcome page loads from the VM

### 10. Demonstrate Automatic Rebuild and Redeploy

Make a visible content change, commit it, and push to your fork. A good proof point is the welcome page build metadata block because it changes on every successful package build.

Then show:

- Jenkins polling triggers a new build
- the new build finishes successfully
- the deployed VM welcome page now shows the updated build details

## Monitoring Flow

- Jenkins exposes metrics at `/prometheus`
- Prometheus scrapes Jenkins and the deployed Spring Boot Actuator endpoint
- Grafana uses the provisioned Prometheus datasource and dashboard JSON

## Reports Produced by the Pipeline

- SonarQube analysis in SonarQube UI
- Dependency Check HTML report in Jenkins
- DAST HTML report in Jenkins
- JUnit test results in Jenkins
- JaCoCo coverage HTML report in Jenkins

## Bonus Automation

Run [scripts/full-automation.sh](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/scripts/full-automation.sh) if you want a guided bootstrap flow for the container stack plus VM inventory generation.
