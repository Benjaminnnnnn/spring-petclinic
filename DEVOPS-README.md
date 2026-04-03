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

### 3. Start the Containerized Toolchain

```bash
chmod 755 setup.sh stop-services.sh
./setup.sh
```

This builds the custom Jenkins image, pulls the other images, and starts:

- Jenkins at `http://localhost:8081`
- SonarQube at `http://localhost:9000`
- Prometheus at `http://localhost:9090`
- Grafana at `http://localhost:3000`
- OWASP ZAP API at `http://localhost:8090`

### 4. Log In to the Services

- Jenkins: `admin / admin`
- SonarQube: `admin / admin`
- Grafana: `admin / admin`

After first SonarQube login, create a user token and export it as `SONARQUBE_TOKEN` for repeatable Jenkins scans.

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

### 7. Configure Deployment Variables in Jenkins

In the Jenkins job or global environment, define:

- `PRODUCTION_VM_HOST`
- `PRODUCTION_VM_USER`

The pipeline skips deployment stages when `PRODUCTION_VM_HOST` is blank, so set it before your final graded run.

### 8. Point Prometheus at the Deployed VM

Edit [prometheus/targets/petclinic.json](/Users/benjaminzhuang/workspace/cmu/spring-petclinic/prometheus/targets/petclinic.json) and replace `host.docker.internal:8080` with `<vm-ip>:8080`, then reload Prometheus:

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
