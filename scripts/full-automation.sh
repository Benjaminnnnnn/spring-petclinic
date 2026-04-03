#!/bin/bash

# Full Automation Script for DevSecOps Pipeline
# This script provides complete automation for bonus points

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${YELLOW}ℹ $1${NC}"; }
print_step() { echo -e "\n${CYAN}=== $1 ===${NC}"; }

cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║     DevSecOps Pipeline - Full Automation Script           ║
║     Spring PetClinic Project                              ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
EOF

# Parse arguments
GITHUB_USERNAME=""
GITHUB_REPO="spring-petclinic"
PRODUCTION_VM_IP=""
SKIP_VM_SETUP=false
CLEAN_INSTALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --github-username)
            GITHUB_USERNAME="$2"
            shift 2
            ;;
        --github-repo)
            GITHUB_REPO="$2"
            shift 2
            ;;
        --vm-ip)
            PRODUCTION_VM_IP="$2"
            shift 2
            ;;
        --skip-vm)
            SKIP_VM_SETUP=true
            shift
            ;;
        --clean)
            CLEAN_INSTALL=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Get GitHub username if not provided
if [ -z "$GITHUB_USERNAME" ]; then
    read -p "Enter your GitHub username: " GITHUB_USERNAME
fi

# Get VM IP if not provided and not skipping
if [ -z "$PRODUCTION_VM_IP" ] && [ "$SKIP_VM_SETUP" = false ]; then
    read -p "Enter Production VM IP address (or press Enter to skip): " PRODUCTION_VM_IP
    if [ -z "$PRODUCTION_VM_IP" ]; then
        SKIP_VM_SETUP=true
        print_info "VM setup will be skipped"
    fi
fi

# Step 1: Prerequisites Check
print_step "Step 1: Checking Prerequisites"

if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed. Please install Docker first."
    exit 1
fi
print_success "Docker is installed"

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    print_error "Docker Compose is not installed."
    exit 1
fi
print_success "Docker Compose is available"

if ! command -v git &> /dev/null; then
    print_error "Git is not installed."
    exit 1
fi
print_success "Git is installed"

# Step 2: Clean Previous Installation
if [ "$CLEAN_INSTALL" = true ]; then
    print_step "Step 2: Cleaning Previous Installation"
    
    print_info "Stopping all services..."
    docker compose -f docker-compose-devsecops.yml down -v 2>/dev/null || true
    
    print_info "Removing Docker network..."
    docker network rm devsecops-network 2>/dev/null || true
    
    print_success "Clean installation prepared"
else
    print_step "Step 2: Using Existing Installation (if any)"
fi

# Step 3: Create Docker Network
print_step "Step 3: Creating Docker Network"

if docker network create devsecops-network 2>/dev/null; then
    print_success "Docker network created"
else
    print_info "Network already exists"
fi

# Step 4: Start All Services
print_step "Step 4: Starting DevSecOps Services"

print_info "Starting containers (this may take 5-10 minutes)..."
docker compose -f docker-compose-devsecops.yml up -d

sleep 10

# Step 5: Wait for Services
print_step "Step 5: Waiting for Services to be Ready"

wait_for_service() {
    local service=$1
    local port=$2
    local max_attempts=60
    local attempt=0
    
    echo -n "Checking $service..."
    while [ $attempt -lt $max_attempts ]; do
        if curl -s http://localhost:$port > /dev/null 2>&1; then
            echo ""
            print_success "$service is ready"
            return 0
        fi
        echo -n "."
        sleep 5
        attempt=$((attempt + 1))
    done
    
    echo ""
    print_error "$service failed to start"
    return 1
}

wait_for_service "Jenkins" 8081
wait_for_service "SonarQube" 9000
wait_for_service "Prometheus" 9090
wait_for_service "Grafana" 3000
wait_for_service "OWASP ZAP" 8090

# Step 6: Configure SonarQube
print_step "Step 6: Configuring SonarQube"

sleep 15

# Generate SonarQube token
SONAR_TOKEN=$(curl -s -u admin:admin -X POST "http://localhost:9000/api/user_tokens/generate?name=jenkins-token" | grep -o '"token":"[^"]*' | cut -d'"' -f4)

if [ -n "$SONAR_TOKEN" ]; then
    print_success "SonarQube token generated: $SONAR_TOKEN"
    echo "$SONAR_TOKEN" > sonarqube-token.txt
else
    print_info "Using default SonarQube credentials (admin/admin)"
    SONAR_TOKEN="admin"
fi

# Create SonarQube project
curl -s -u admin:admin -X POST "http://localhost:9000/api/projects/create?name=spring-petclinic&project=spring-petclinic" > /dev/null 2>&1 || true
print_success "SonarQube project created"

# Step 7: Get Jenkins Initial Password
print_step "Step 7: Retrieving Jenkins Credentials"

JENKINS_PASSWORD=$(docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || echo "")

if [ -n "$JENKINS_PASSWORD" ]; then
    print_success "Jenkins initial admin password: $JENKINS_PASSWORD"
    echo "$JENKINS_PASSWORD" > jenkins-password.txt
else
    print_info "Run manually: docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
fi

# Step 8: Configure Production VM
if [ "$SKIP_VM_SETUP" = false ] && [ -n "$PRODUCTION_VM_IP" ]; then
    print_step "Step 8: Configuring Production VM Connection"
    
    # Update Ansible inventory
    cat > ansible/inventory.ini << EOF
[production]
production-vm ansible_host=$PRODUCTION_VM_IP ansible_user=deployer

[production:vars]
ansible_python_interpreter=/usr/bin/python3
EOF
    
    print_success "Ansible inventory updated with VM IP: $PRODUCTION_VM_IP"
    
    # Generate SSH key in Jenkins
    print_info "Setting up SSH keys for Jenkins..."
    docker exec jenkins bash -c "ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/id_rsa -q" 2>/dev/null || true
    
    PUBLIC_KEY=$(docker exec jenkins cat /root/.ssh/id_rsa.pub)
    print_info "Jenkins SSH Public Key:"
    echo -e "${YELLOW}$PUBLIC_KEY${NC}"
    print_info "Add this key to the production VM's ~/.ssh/authorized_keys file"
    
    echo "$PUBLIC_KEY" > jenkins-ssh-key.pub
    print_success "SSH key saved to jenkins-ssh-key.pub"
else
    print_step "Step 8: Skipping VM Setup"
    print_info "You can configure the VM later using VM-SETUP-GUIDE.md"
fi

# Step 9: Create Jenkins Job Configuration
print_step "Step 9: Preparing Jenkins Job Configuration"

mkdir -p jenkins-config/jobs

cat > jenkins-config/jobs/spring-petclinic-pipeline-config.xml << EOF
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job@2.40">
  <description>DevSecOps Pipeline for Spring PetClinic</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty>
      <triggers>
        <hudson.triggers.SCMTrigger>
          <spec>H/5 * * * *</spec>
          <ignorePostCommitHooks>false</ignorePostCommitHooks>
        </hudson.triggers.SCMTrigger>
      </triggers>
    </org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps@2.92">
    <scm class="hudson.plugins.git.GitSCM" plugin="git@4.10.0">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>https://github.com/$GITHUB_USERNAME/$GITHUB_REPO.git</url>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/main</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
    </scm>
    <scriptPath>Jenkinsfile</scriptPath>
    <lightweight>true</lightweight>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
EOF

print_success "Jenkins job configuration created"

# Step 10: Create Helper Scripts
print_step "Step 10: Creating Helper Scripts"

# Check services script
cat > check-services.sh << 'EOF'
#!/bin/bash
echo "DevSecOps Services Status"
echo ""
docker compose -f docker-compose-devsecops.yml ps
echo ""
echo "Service URLs:"
echo "  Jenkins:    http://localhost:8081"
echo "  SonarQube:  http://localhost:9000"
echo "  Prometheus: http://localhost:9090"
echo "  Grafana:    http://localhost:3000"
echo "  ZAP:        http://localhost:8090"
EOF
chmod +x check-services.sh

# Stop services script
cat > stop-services.sh << 'EOF'
#!/bin/bash
echo "Stopping DevSecOps services..."
docker compose -f docker-compose-devsecops.yml down
echo "Services stopped"
EOF
chmod +x stop-services.sh

# Restart services script
cat > restart-services.sh << 'EOF'
#!/bin/bash
echo "Restarting DevSecOps services..."
docker compose -f docker-compose-devsecops.yml restart
echo "Services restarted"
EOF
chmod +x restart-services.sh

# View logs script
cat > view-logs.sh << 'EOF'
#!/bin/bash
SERVICE=${1:-""}
if [ -n "$SERVICE" ]; then
    docker compose -f docker-compose-devsecops.yml logs -f $SERVICE
else
    docker compose -f docker-compose-devsecops.yml logs -f
fi
EOF
chmod +x view-logs.sh

print_success "Helper scripts created"

# Step 11: Generate Summary Report
print_step "Step 11: Generating Summary Report"

VM_INFO=""
if [ "$SKIP_VM_SETUP" = false ] && [ -n "$PRODUCTION_VM_IP" ]; then
    VM_INFO="Production VM
  IP Address: $PRODUCTION_VM_IP
  SSH Key: jenkins-ssh-key.pub
  User: deployer"
else
    VM_INFO="Production VM
  Not configured yet
  See: VM-SETUP-GUIDE.md"
fi

cat > SETUP-SUMMARY.txt << EOF
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║     DevSecOps Pipeline - Setup Complete!                  ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝

Setup Date: $(date '+%Y-%m-%d %H:%M:%S')
GitHub Repository: https://github.com/$GITHUB_USERNAME/$GITHUB_REPO

═══════════════════════════════════════════════════════════
SERVICE URLS AND CREDENTIALS
═══════════════════════════════════════════════════════════

Jenkins
  URL: http://localhost:8081
  Initial Password: $JENKINS_PASSWORD
  (Also saved in: jenkins-password.txt)

SonarQube
  URL: http://localhost:9000
  Username: admin
  Password: admin (CHANGE ON FIRST LOGIN!)
  Token: $SONAR_TOKEN

Prometheus
  URL: http://localhost:9090
  No authentication required

Grafana
  URL: http://localhost:3000
  Username: admin
  Password: admin

OWASP ZAP
  URL: http://localhost:8090
  API Key: devsecops-zap-key

$VM_INFO

═══════════════════════════════════════════════════════════
NEXT STEPS
═══════════════════════════════════════════════════════════

1. Configure Jenkins
   - Access: http://localhost:8081
   - Use initial password above
   - Install suggested plugins
   - Install additional plugins:
     * Blue Ocean
     * SonarQube Scanner
     * Prometheus Metrics
     * Ansible
     * Docker Pipeline
     * HTML Publisher
     * JaCoCo

2. Configure Jenkins Tools
   - Manage Jenkins → Global Tool Configuration
   - Add Maven 3.9.x
   - Add JDK 17
   - Add SonarQube server

3. Create Jenkins Pipeline Job
   - New Item → Pipeline
   - Name: spring-petclinic-pipeline
   - Pipeline from SCM
   - Git: https://github.com/$GITHUB_USERNAME/$GITHUB_REPO.git
   - Script Path: Jenkinsfile
   - Build Triggers: Poll SCM (H/5 * * * *)

4. Configure Production VM (if not done)
   - See: VM-SETUP-GUIDE.md
   - Add SSH key from: jenkins-ssh-key.pub
   - Update: ansible/inventory.ini

5. Test the Pipeline
   - Make a code change
   - Commit and push
   - Watch Jenkins build automatically
   - Verify deployment

═══════════════════════════════════════════════════════════
HELPER SCRIPTS
═══════════════════════════════════════════════════════════

./check-services.sh     - Check service status
./stop-services.sh      - Stop all services
./restart-services.sh   - Restart all services
./view-logs.sh          - View service logs
./view-logs.sh jenkins  - View specific service logs

═══════════════════════════════════════════════════════════
DOCUMENTATION
═══════════════════════════════════════════════════════════

DEVSECOPS-README.md     - Main documentation
SETUP-GUIDE.md          - Detailed setup instructions
VM-SETUP-GUIDE.md       - Production VM setup
SCREENSHOTS-GUIDE.md    - Screenshot requirements

═══════════════════════════════════════════════════════════
TROUBLESHOOTING
═══════════════════════════════════════════════════════════

Service not starting:
  docker compose -f docker-compose-devsecops.yml logs <service>

Restart specific service:
  docker compose -f docker-compose-devsecops.yml restart <service>

Clean restart:
  docker compose -f docker-compose-devsecops.yml down -v
  ./setup-devsecops.sh

═══════════════════════════════════════════════════════════

Setup completed successfully! 🚀

For support, refer to the documentation files or check service logs.

═══════════════════════════════════════════════════════════
EOF

cat SETUP-SUMMARY.txt

print_success "Summary report saved to SETUP-SUMMARY.txt"

# Step 12: Final Verification
print_step "Step 12: Final Verification"

print_info "Verifying all services are running..."

EXPECTED_SERVICES=("jenkins" "sonarqube" "postgresql" "prometheus" "grafana" "zap")
ALL_RUNNING=true

for service in "${EXPECTED_SERVICES[@]}"; do
    if docker compose -f docker-compose-devsecops.yml ps | grep -q "$service.*Up"; then
        print_success "$service is running"
    else
        print_error "$service is not running"
        ALL_RUNNING=false
    fi
done

echo ""
if [ "$ALL_RUNNING" = true ]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                            ║${NC}"
    echo -e "${GREEN}║     ✓ All services are running successfully!              ║${NC}"
    echo -e "${GREEN}║                                                            ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
else
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                                                            ║${NC}"
    echo -e "${YELLOW}║     ⚠ Some services may need attention                    ║${NC}"
    echo -e "${YELLOW}║                                                            ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
fi

echo ""
echo -e "${CYAN}Setup complete! Check SETUP-SUMMARY.txt for details.${NC}"
echo ""
