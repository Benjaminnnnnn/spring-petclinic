#!/bin/bash

# DevSecOps Pipeline Setup Script
# This script automates the complete setup of the DevSecOps environment

set -e

echo "=========================================="
echo "DevSecOps Pipeline Setup"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed. Please install Docker first."
    exit 1
fi
print_success "Docker is installed"

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    print_error "Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi
print_success "Docker Compose is installed"

# Create custom Docker network
echo ""
echo "Creating custom Docker network..."
docker network create devsecops-network 2>/dev/null || print_info "Network already exists"
print_success "Docker network ready"

# Start all services
echo ""
echo "Starting DevSecOps services..."
print_info "This may take several minutes on first run..."

docker-compose -f docker-compose-devsecops.yml up -d

# Wait for services to be healthy
echo ""
echo "Waiting for services to be ready..."

wait_for_service() {
    local service=$1
    local port=$2
    local max_attempts=60
    local attempt=0
    
    echo -n "Waiting for $service..."
    while [ $attempt -lt $max_attempts ]; do
        if curl -s http://localhost:$port > /dev/null 2>&1; then
            print_success "$service is ready"
            return 0
        fi
        echo -n "."
        sleep 5
        attempt=$((attempt + 1))
    done
    
    print_error "$service failed to start"
    return 1
}

wait_for_service "Jenkins" 8081
wait_for_service "SonarQube" 9000
wait_for_service "Prometheus" 9090
wait_for_service "Grafana" 3000
wait_for_service "ZAP" 8090

# Configure SonarQube
echo ""
echo "Configuring SonarQube..."

# Wait a bit more for SonarQube to fully initialize
sleep 10

# Create SonarQube token and project
SONAR_TOKEN=$(curl -s -u admin:admin -X POST "http://localhost:9000/api/user_tokens/generate?name=jenkins" | grep -o '"token":"[^"]*' | cut -d'"' -f4)

if [ -z "$SONAR_TOKEN" ]; then
    print_info "Using default SonarQube credentials (admin/admin)"
    print_info "Please change the password on first login"
    SONAR_TOKEN="admin"
fi

# Create SonarQube project
curl -s -u admin:admin -X POST "http://localhost:9000/api/projects/create?name=spring-petclinic&project=spring-petclinic" > /dev/null 2>&1 || true

print_success "SonarQube configured"

# Get Jenkins initial admin password
echo ""
echo "=========================================="
echo "Service URLs and Credentials"
echo "=========================================="
echo ""
echo "Jenkins:"
echo "  URL: http://localhost:8081"
echo "  Initial Admin Password: (check container logs)"
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || print_info "Run: docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
echo ""
echo "SonarQube:"
echo "  URL: http://localhost:9000"
echo "  Username: admin"
echo "  Password: admin (change on first login)"
echo "  Token: $SONAR_TOKEN"
echo ""
echo "Prometheus:"
echo "  URL: http://localhost:9090"
echo ""
echo "Grafana:"
echo "  URL: http://localhost:3000"
echo "  Username: admin"
echo "  Password: admin"
echo ""
echo "OWASP ZAP:"
echo "  URL: http://localhost:8090"
echo "  API Key: devsecops-zap-key"
echo ""

# Create Jenkins configuration script
echo ""
echo "Creating Jenkins configuration..."

mkdir -p jenkins-config

cat > jenkins-config/plugins.txt << 'EOF'
blueocean
pipeline-utility-steps
sonar
prometheus
ansible
docker-workflow
git
workflow-aggregator
credentials-binding
ssh-agent
publish-over-ssh
htmlpublisher
jacoco
junit
EOF

print_success "Jenkins plugin list created"

# Create helper scripts
cat > check-services.sh << 'EOF'
#!/bin/bash
echo "Checking DevSecOps services status..."
echo ""
docker-compose -f docker-compose-devsecops.yml ps
echo ""
echo "Service URLs:"
echo "  Jenkins:    http://localhost:8081"
echo "  SonarQube:  http://localhost:9000"
echo "  Prometheus: http://localhost:9090"
echo "  Grafana:    http://localhost:3000"
echo "  ZAP:        http://localhost:8090"
EOF

chmod +x check-services.sh

cat > stop-services.sh << 'EOF'
#!/bin/bash
echo "Stopping DevSecOps services..."
docker-compose -f docker-compose-devsecops.yml down
echo "Services stopped"
EOF

chmod +x stop-services.sh

cat > restart-services.sh << 'EOF'
#!/bin/bash
echo "Restarting DevSecOps services..."
docker-compose -f docker-compose-devsecops.yml restart
echo "Services restarted"
EOF

chmod +x restart-services.sh

print_success "Helper scripts created"

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
print_success "All services are running"
echo ""
echo "Next Steps:"
echo "1. Access Jenkins at http://localhost:8081"
echo "2. Install suggested plugins and create admin user"
echo "3. Configure Jenkins:"
echo "   - Install required plugins from jenkins-config/plugins.txt"
echo "   - Add SonarQube server configuration"
echo "   - Configure Maven and JDK tools"
echo "   - Create a new Pipeline job pointing to your GitHub repository"
echo "4. Access Grafana at http://localhost:3000 and explore dashboards"
echo "5. Set up your production VM and update ansible/inventory.ini"
echo ""
echo "Helper scripts:"
echo "  ./check-services.sh   - Check service status"
echo "  ./stop-services.sh    - Stop all services"
echo "  ./restart-services.sh - Restart all services"
echo ""
print_info "Documentation available in SETUP-GUIDE.md"
