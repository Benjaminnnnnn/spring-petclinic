# Full Automation Script for DevSecOps Pipeline
# This script provides complete automation for bonus points

param(
    [string]$GitHubUsername = "",
    [string]$GitHubRepo = "spring-petclinic",
    [string]$ProductionVMIP = "",
    [switch]$SkipVMSetup = $false,
    [switch]$CleanInstall = $false
)

$ErrorActionPreference = "Stop"

# Colors
function Write-Success { param($msg) Write-Host "✓ $msg" -ForegroundColor Green }
function Write-Error { param($msg) Write-Host "✗ $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "ℹ $msg" -ForegroundColor Yellow }
function Write-Step { param($msg) Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

Write-Host @"
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║     DevSecOps Pipeline - Full Automation Script           ║
║     Spring PetClinic Project                              ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

# Validate inputs
if (-not $GitHubUsername) {
    $GitHubUsername = Read-Host "Enter your GitHub username"
}

if (-not $ProductionVMIP -and -not $SkipVMSetup) {
    $ProductionVMIP = Read-Host "Enter Production VM IP address (or press Enter to skip VM setup)"
    if (-not $ProductionVMIP) {
        $SkipVMSetup = $true
        Write-Info "VM setup will be skipped"
    }
}

# Step 1: Prerequisites Check
Write-Step "Step 1: Checking Prerequisites"

try {
    docker --version | Out-Null
    Write-Success "Docker is installed"
} catch {
    Write-Error "Docker is not installed. Please install Docker Desktop."
    exit 1
}

try {
    docker compose version | Out-Null
    Write-Success "Docker Compose is available"
} catch {
    Write-Error "Docker Compose is not available."
    exit 1
}

try {
    git --version | Out-Null
    Write-Success "Git is installed"
} catch {
    Write-Error "Git is not installed."
    exit 1
}

# Step 2: Clean Previous Installation (if requested)
if ($CleanInstall) {
    Write-Step "Step 2: Cleaning Previous Installation"
    
    Write-Info "Stopping all services..."
    docker compose -f docker-compose-devsecops.yml down -v 2>$null
    
    Write-Info "Removing Docker network..."
    docker network rm devsecops-network 2>$null
    
    Write-Success "Clean installation prepared"
} else {
    Write-Step "Step 2: Using Existing Installation (if any)"
}

# Step 3: Create Docker Network
Write-Step "Step 3: Creating Docker Network"

try {
    docker network create devsecops-network 2>$null
    Write-Success "Docker network created"
} catch {
    Write-Info "Network already exists"
}

# Step 4: Start All Services
Write-Step "Step 4: Starting DevSecOps Services"

Write-Info "Starting containers (this may take 5-10 minutes)..."
docker compose -f docker-compose-devsecops.yml up -d

Start-Sleep -Seconds 10

# Step 5: Wait for Services
Write-Step "Step 5: Waiting for Services to be Ready"

function Wait-ForService {
    param($Name, $Port, $MaxAttempts = 60)
    
    Write-Host "Checking $Name..." -NoNewline
    for ($i = 0; $i -lt $MaxAttempts; $i++) {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$Port" -UseBasicParsing -TimeoutSec 2 -ErrorAction SilentlyContinue
            Write-Host ""
            Write-Success "$Name is ready"
            return $true
        } catch {
            Write-Host "." -NoNewline
            Start-Sleep -Seconds 5
        }
    }
    Write-Host ""
    Write-Error "$Name failed to start"
    return $false
}

$services = @(
    @{Name="Jenkins"; Port=8081},
    @{Name="SonarQube"; Port=9000},
    @{Name="Prometheus"; Port=9090},
    @{Name="Grafana"; Port=3000},
    @{Name="OWASP ZAP"; Port=8090}
)

$allReady = $true
foreach ($service in $services) {
    if (-not (Wait-ForService -Name $service.Name -Port $service.Port)) {
        $allReady = $false
    }
}

if (-not $allReady) {
    Write-Error "Some services failed to start. Check logs with: docker compose -f docker-compose-devsecops.yml logs"
    exit 1
}

# Step 6: Configure SonarQube
Write-Step "Step 6: Configuring SonarQube"

Start-Sleep -Seconds 15

try {
    $sonarAuth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:admin"))
    
    # Generate token
    $tokenResponse = Invoke-RestMethod -Uri "http://localhost:9000/api/user_tokens/generate?name=jenkins-token" `
        -Method Post `
        -Headers @{Authorization = "Basic $sonarAuth"} `
        -ErrorAction SilentlyContinue
    
    $sonarToken = $tokenResponse.token
    Write-Success "SonarQube token generated: $sonarToken"
    
    # Create project
    Invoke-RestMethod -Uri "http://localhost:9000/api/projects/create?name=spring-petclinic&project=spring-petclinic" `
        -Method Post `
        -Headers @{Authorization = "Basic $sonarAuth"} `
        -ErrorAction SilentlyContinue | Out-Null
    
    Write-Success "SonarQube project created"
    
    # Save token for later use
    $sonarToken | Out-File -FilePath "sonarqube-token.txt"
    
} catch {
    Write-Info "SonarQube configuration may need manual setup"
    Write-Info "Default credentials: admin/admin"
}

# Step 7: Get Jenkins Initial Password
Write-Step "Step 7: Retrieving Jenkins Credentials"

try {
    $jenkinsPassword = docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword 2>$null
    Write-Success "Jenkins initial admin password: $jenkinsPassword"
    $jenkinsPassword | Out-File -FilePath "jenkins-password.txt"
} catch {
    Write-Info "Run manually: docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
}

# Step 8: Configure Production VM (if provided)
if (-not $SkipVMSetup -and $ProductionVMIP) {
    Write-Step "Step 8: Configuring Production VM Connection"
    
    # Update Ansible inventory
    $inventoryContent = @"
[production]
production-vm ansible_host=$ProductionVMIP ansible_user=deployer

[production:vars]
ansible_python_interpreter=/usr/bin/python3
"@
    
    $inventoryContent | Out-File -FilePath "ansible\inventory.ini" -Encoding UTF8
    Write-Success "Ansible inventory updated with VM IP: $ProductionVMIP"
    
    # Generate SSH key in Jenkins
    Write-Info "Setting up SSH keys for Jenkins..."
    docker exec jenkins bash -c "ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/id_rsa -q" 2>$null
    
    $publicKey = docker exec jenkins cat /root/.ssh/id_rsa.pub
    Write-Info "Jenkins SSH Public Key:"
    Write-Host $publicKey -ForegroundColor Yellow
    Write-Info "Add this key to the production VM's ~/.ssh/authorized_keys file"
    
    $publicKey | Out-File -FilePath "jenkins-ssh-key.pub"
    Write-Success "SSH key saved to jenkins-ssh-key.pub"
} else {
    Write-Step "Step 8: Skipping VM Setup"
    Write-Info "You can configure the VM later using VM-SETUP-GUIDE.md"
}

# Step 9: Create Jenkins Job Configuration
Write-Step "Step 9: Preparing Jenkins Job Configuration"

$jobConfig = @"
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
          <url>https://github.com/$GitHubUsername/$GitHubRepo.git</url>
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
"@

New-Item -ItemType Directory -Force -Path "jenkins-config\jobs" | Out-Null
$jobConfig | Out-File -FilePath "jenkins-config\jobs\spring-petclinic-pipeline-config.xml" -Encoding UTF8
Write-Success "Jenkins job configuration created"

# Step 10: Create Helper Scripts
Write-Step "Step 10: Creating Helper Scripts"

# Check services script
@"
Write-Host "DevSecOps Services Status" -ForegroundColor Cyan
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

# Stop services script
@"
Write-Host "Stopping DevSecOps services..." -ForegroundColor Yellow
docker compose -f docker-compose-devsecops.yml down
Write-Host "Services stopped" -ForegroundColor Green
"@ | Out-File -FilePath "stop-services.ps1" -Encoding UTF8

# Restart services script
@"
Write-Host "Restarting DevSecOps services..." -ForegroundColor Yellow
docker compose -f docker-compose-devsecops.yml restart
Write-Host "Services restarted" -ForegroundColor Green
"@ | Out-File -FilePath "restart-services.ps1" -Encoding UTF8

# View logs script
@"
param([string]`$Service = "")
if (`$Service) {
    docker compose -f docker-compose-devsecops.yml logs -f `$Service
} else {
    docker compose -f docker-compose-devsecops.yml logs -f
}
"@ | Out-File -FilePath "view-logs.ps1" -Encoding UTF8

Write-Success "Helper scripts created"

# Step 11: Generate Summary Report
Write-Step "Step 11: Generating Summary Report"

$summaryReport = @"
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║     DevSecOps Pipeline - Setup Complete!                  ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝

Setup Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
GitHub Repository: https://github.com/$GitHubUsername/$GitHubRepo

═══════════════════════════════════════════════════════════
SERVICE URLS AND CREDENTIALS
═══════════════════════════════════════════════════════════

Jenkins
  URL: http://localhost:8081
  Initial Password: $jenkinsPassword
  (Also saved in: jenkins-password.txt)

SonarQube
  URL: http://localhost:9000
  Username: admin
  Password: admin (CHANGE ON FIRST LOGIN!)
  Token: $(if (Test-Path "sonarqube-token.txt") { Get-Content "sonarqube-token.txt" } else { "Generate manually" })

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

$(if (-not $SkipVMSetup -and $ProductionVMIP) {
"Production VM
  IP Address: $ProductionVMIP
  SSH Key: jenkins-ssh-key.pub
  User: deployer"
} else {
"Production VM
  Not configured yet
  See: VM-SETUP-GUIDE.md"
})

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
   - Git: https://github.com/$GitHubUsername/$GitHubRepo.git
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

.\check-services.ps1    - Check service status
.\stop-services.ps1     - Stop all services
.\restart-services.ps1  - Restart all services
.\view-logs.ps1         - View service logs
.\view-logs.ps1 jenkins - View specific service logs

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
  .\setup-devsecops.ps1

═══════════════════════════════════════════════════════════

Setup completed successfully! 🚀

For support, refer to the documentation files or check service logs.

═══════════════════════════════════════════════════════════
"@

$summaryReport | Out-File -FilePath "SETUP-SUMMARY.txt" -Encoding UTF8
Write-Host $summaryReport -ForegroundColor White

Write-Success "Summary report saved to SETUP-SUMMARY.txt"

# Step 12: Final Verification
Write-Step "Step 12: Final Verification"

Write-Info "Verifying all services are running..."
$runningServices = docker compose -f docker-compose-devsecops.yml ps --format json | ConvertFrom-Json

$expectedServices = @("jenkins", "sonarqube", "postgresql", "prometheus", "grafana", "zap")
$allRunning = $true

foreach ($expected in $expectedServices) {
    $found = $runningServices | Where-Object { $_.Service -eq $expected -or $_.Name -like "*$expected*" }
    if ($found) {
        Write-Success "$expected is running"
    } else {
        Write-Error "$expected is not running"
        $allRunning = $false
    }
}

if ($allRunning) {
    Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                                                            ║" -ForegroundColor Green
    Write-Host "║     ✓ All services are running successfully!              ║" -ForegroundColor Green
    Write-Host "║                                                            ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Green
} else {
    Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║                                                            ║" -ForegroundColor Yellow
    Write-Host "║     ⚠ Some services may need attention                    ║" -ForegroundColor Yellow
    Write-Host "║                                                            ║" -ForegroundColor Yellow
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
}

Write-Host "`nSetup complete! Check SETUP-SUMMARY.txt for details.`n" -ForegroundColor Cyan
