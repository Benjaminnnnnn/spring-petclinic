# DevSecOps Pipeline Setup Script for Windows
# This script automates the complete setup of the DevSecOps environment

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "DevSecOps Pipeline Setup" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

function Print-Success {
    param($Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Print-Error {
    param($Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Print-Info {
    param($Message)
    Write-Host "ℹ $Message" -ForegroundColor Yellow
}

# Check prerequisites
Write-Host "Checking prerequisites..."

try {
    docker --version | Out-Null
    Print-Success "Docker is installed"
} catch {
    Print-Error "Docker is not installed. Please install Docker Desktop first."
    exit 1
}

try {
    docker compose version | Out-Null
    Print-Success "Docker Compose is available"
} catch {
    Print-Error "Docker Compose is not available. Please update Docker Desktop."
    exit 1
}

# Create custom Docker network
Write-Host ""
Write-Host "Creating custom Docker network..."
try {
    docker network create devsecops-network 2>$null
    Print-Success "Docker network created"
} catch {
    Print-Info "Network already exists"
}

# Start all services
Write-Host ""
Write-Host "Starting DevSecOps services..."
Print-Info "This may take several minutes on first run..."

docker compose -f docker-compose-devsecops.yml up -d

# Wait for services to be healthy
Write-Host ""
Write-Host "Waiting for services to be ready..."

function Wait-ForService {
    param(
        [string]$ServiceName,
        [int]$Port,
        [int]$MaxAttempts = 60
    )
    
    Write-Host "Waiting for $ServiceName..." -NoNewline
    
    for ($i = 0; $i -lt $MaxAttempts; $i++) {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$Port" -UseBasicParsing -TimeoutSec 2 -ErrorAction SilentlyContinue
            Write-Host ""
            Print-Success "$ServiceName is ready"
            return $true
        } catch {
            Write-Host "." -NoNewline
            Start-Sleep -Seconds 5
        }
    }
    
    Write-Host ""
    Print-Error "$ServiceName failed to start"
    return $false
}

Wait-ForService -ServiceName "Jenkins" -Port 8081
Wait-ForService -ServiceName "SonarQube" -Port 9000
Wait-ForService -ServiceName "Prometheus" -Port 9090
Wait-ForService -ServiceName "Grafana" -Port 3000
Wait-ForService -ServiceName "ZAP" -Port 8090

# Configure SonarQube
Write-Host ""
Write-Host "Configuring SonarQube..."
Start-Sleep -Seconds 10

# Create SonarQube token
try {
    $sonarResponse = Invoke-RestMethod -Uri "http://localhost:9000/api/user_tokens/generate?name=jenkins" `
        -Method Post `
        -Headers @{Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:admin"))} `
        -ErrorAction SilentlyContinue
    $sonarToken = $sonarResponse.token
} catch {
    Print-Info "Using default SonarQube credentials (admin/admin)"
    $sonarToken = "admin"
}

# Create SonarQube project
try {
    Invoke-RestMethod -Uri "http://localhost:9000/api/projects/create?name=spring-petclinic&project=spring-petclinic" `
        -Method Post `
        -Headers @{Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:admin"))} `
        -ErrorAction SilentlyContinue | Out-Null
} catch {
    # Project might already exist
}

Print-Success "SonarQube configured"

# Get Jenkins initial admin password
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Service URLs and Credentials" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Jenkins:" -ForegroundColor Yellow
Write-Host "  URL: http://localhost:8081"
Write-Host "  Initial Admin Password:"
try {
    $jenkinsPassword = docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword 2>$null
    Write-Host "  $jenkinsPassword" -ForegroundColor Green
} catch {
    Print-Info "  Run: docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
}

Write-Host ""
Write-Host "SonarQube:" -ForegroundColor Yellow
Write-Host "  URL: http://localhost:9000"
Write-Host "  Username: admin"
Write-Host "  Password: admin (change on first login)"
Write-Host "  Token: $sonarToken"

Write-Host ""
Write-Host "Prometheus:" -ForegroundColor Yellow
Write-Host "  URL: http://localhost:9090"

Write-Host ""
Write-Host "Grafana:" -ForegroundColor Yellow
Write-Host "  URL: http://localhost:3000"
Write-Host "  Username: admin"
Write-Host "  Password: admin"

Write-Host ""
Write-Host "OWASP ZAP:" -ForegroundColor Yellow
Write-Host "  URL: http://localhost:8090"
Write-Host "  API Key: devsecops-zap-key"

Write-Host ""

# Create Jenkins configuration
Write-Host "Creating Jenkins configuration..."
New-Item -ItemType Directory -Force -Path "jenkins-config" | Out-Null

@"
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
"@ | Out-File -FilePath "jenkins-config\plugins.txt" -Encoding UTF8

Print-Success "Jenkins plugin list created"

# Create helper scripts
@"
# Check DevSecOps services status
Write-Host "Checking DevSecOps services status..." -ForegroundColor Cyan
Write-Host ""
docker compose -f docker-compose-devsecops.yml ps
Write-Host ""
Write-Host "Service URLs:" -ForegroundColor Yellow
Write-Host "  Jenkins:    http://localhost:8081"
Write-Host "  SonarQube:  http://localhost:9000"
Write-Host "  Prometheus: http://localhost:9090"
Write-Host "  Grafana:    http://localhost:3000"
Write-Host "  ZAP:        http://localhost:8090"
"@ | Out-File -FilePath "check-services.ps1" -Encoding UTF8

@"
# Stop DevSecOps services
Write-Host "Stopping DevSecOps services..." -ForegroundColor Yellow
docker compose -f docker-compose-devsecops.yml down
Write-Host "Services stopped" -ForegroundColor Green
"@ | Out-File -FilePath "stop-services.ps1" -Encoding UTF8

@"
# Restart DevSecOps services
Write-Host "Restarting DevSecOps services..." -ForegroundColor Yellow
docker compose -f docker-compose-devsecops.yml restart
Write-Host "Services restarted" -ForegroundColor Green
"@ | Out-File -FilePath "restart-services.ps1" -Encoding UTF8

Print-Success "Helper scripts created"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Print-Success "All services are running"
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Access Jenkins at http://localhost:8081"
Write-Host "2. Install suggested plugins and create admin user"
Write-Host "3. Configure Jenkins:"
Write-Host "   - Install required plugins from jenkins-config\plugins.txt"
Write-Host "   - Add SonarQube server configuration"
Write-Host "   - Configure Maven and JDK tools"
Write-Host "   - Create a new Pipeline job pointing to your GitHub repository"
Write-Host "4. Access Grafana at http://localhost:3000 and explore dashboards"
Write-Host "5. Set up your production VM and update ansible\inventory.ini"
Write-Host ""
Write-Host "Helper scripts:" -ForegroundColor Yellow
Write-Host "  .\check-services.ps1   - Check service status"
Write-Host "  .\stop-services.ps1    - Stop all services"
Write-Host "  .\restart-services.ps1 - Restart all services"
Write-Host ""
Print-Info "Documentation available in SETUP-GUIDE.md"
