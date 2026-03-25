# Script to pre-download all Docker images
# This helps avoid timeout issues during docker-compose up

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Pulling Docker Images for DevSecOps" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Set longer timeout
$env:DOCKER_CLIENT_TIMEOUT="600"
$env:COMPOSE_HTTP_TIMEOUT="600"

$images = @(
    @{Name="PostgreSQL"; Image="postgres:15-alpine"; Size="Small"},
    @{Name="Prometheus"; Image="prom/prometheus:latest"; Size="Medium"},
    @{Name="Grafana"; Image="grafana/grafana:latest"; Size="Medium"},
    @{Name="Jenkins"; Image="jenkins/jenkins:lts-jdk17"; Size="Large"},
    @{Name="SonarQube"; Image="sonarqube:lts-community"; Size="Large"},
    @{Name="OWASP ZAP"; Image="zaproxy/zap-stable"; Size="Large"}
)

$totalImages = $images.Count
$currentImage = 0

foreach ($img in $images) {
    $currentImage++
    Write-Host "[$currentImage/$totalImages] Pulling $($img.Name) ($($img.Size))..." -ForegroundColor Yellow
    Write-Host "Image: $($img.Image)" -ForegroundColor Gray
    
    try {
        # Pull with retry logic
        $maxRetries = 3
        $retryCount = 0
        $success = $false
        
        while (-not $success -and $retryCount -lt $maxRetries) {
            try {
                docker pull $img.Image
                $success = $true
                Write-Host "✓ $($img.Name) downloaded successfully" -ForegroundColor Green
            }
            catch {
                $retryCount++
                if ($retryCount -lt $maxRetries) {
                    Write-Host "⚠ Retry $retryCount/$maxRetries for $($img.Name)..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 5
                }
                else {
                    Write-Host "✗ Failed to download $($img.Name) after $maxRetries attempts" -ForegroundColor Red
                    Write-Host "Error: $_" -ForegroundColor Red
                }
            }
        }
    }
    catch {
        Write-Host "✗ Error pulling $($img.Name): $_" -ForegroundColor Red
    }
    
    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Image Download Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Check which images are available
Write-Host ""
Write-Host "Verifying downloaded images..." -ForegroundColor Yellow
Write-Host ""

foreach ($img in $images) {
    $imageExists = docker images $img.Image -q
    if ($imageExists) {
        Write-Host "✓ $($img.Name): Available" -ForegroundColor Green
    }
    else {
        Write-Host "✗ $($img.Name): Missing" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "All images downloaded! Now run:" -ForegroundColor Green
Write-Host "  docker compose -f docker-compose-devsecops.yml up -d" -ForegroundColor White
Write-Host ""
Write-Host "Or use the setup script:" -ForegroundColor Green
Write-Host "  .\setup-devsecops.ps1" -ForegroundColor White
Write-Host ""
