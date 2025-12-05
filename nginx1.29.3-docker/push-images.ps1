# 用法（在專案根目錄）:
#  powershell -File .\nginx1.29.3-docker\push-images.ps1
# powershell -File .\nginx1.29.3-docker\push-images.ps1 -NginxVersion 1.29.3 -HaproxyVersion 3.3.0
# powershell -File .\nginx1.29.3-docker\push-images.ps1 -AutoDetectVersion -Verbose

Param(
  [string]$NginxVersion,
  [string]$HaproxyVersion = "3.3.0",
  [switch]$AutoDetectVersion,
  [switch]$ValidateOnly,
  [switch]$SkipNginx,
  [switch]$SkipHaproxy
)

$ErrorActionPreference = "Stop"

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)

# Image base names
$nginxImageBase = "tw199501/nginx"
$haproxyImageBase = "tw199501/haproxy"

# Log function
function Write-Log {
  param([string]$Message, [string]$Level = "INFO", [string]$Color = "White")

  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $logMessage = "[$timestamp] [$Level] $Message"
  Write-Host $logMessage -ForegroundColor $Color
}

# Check if Docker is running
function Test-DockerRunning {
  try {
    docker info | Out-Null
    return $true
  }
  catch {
    Write-Log "Docker is not running or inaccessible" "ERROR" "Red"
    exit 1
  }
}

# Auto-detect versions
function Get-AutoDetectedVersions {
  Write-Log "Auto-detecting versions..." "INFO" "Cyan"

  $detectedVersions = @{}

  # Detect Nginx version from Dockerfile
  $dockerfilePath = Join-Path $ScriptDir "Dockerfile"
  if (Test-Path $dockerfilePath) {
    $dockerfileContent = Get-Content $dockerfilePath
    foreach ($line in $dockerfileContent) {
      if ($line -match "NGINX_VERSION\s*=\s*[`"']?([0-9.]+)[`"']?") {
        $detectedVersions.Nginx = $matches[1]
        Write-Log "Detected Nginx version from Dockerfile: $($detectedVersions.Nginx)" "INFO" "Green"
        break
      }
    }
  }

  # Detect versions from docker-compose.yml
  $composePath = Join-Path $ScriptDir "docker-compose.yml"
  if (Test-Path $composePath) {
    $composeContent = Get-Content $composePath

    # Detect Nginx version
    foreach ($line in $composeContent) {
      if ($line -match "image:\s*[^:]+:([0-9.]+)" -and -not $detectedVersions.Nginx) {
        $detectedVersions.Nginx = $matches[1]
        Write-Log "Detected Nginx version from docker-compose.yml: $($detectedVersions.Nginx)" "INFO" "Green"
        break
      }
    }

    # Detect HAProxy version
    foreach ($line in $composeContent) {
      if ($line -match "image:\s*[^:]+:(trixie|bullseye|buster|sid|[0-9]+\.[0-9]+\.[0-9]+)") {
        $detectedVersions.Haproxy = $matches[1]
        Write-Log "Detected HAProxy version from docker-compose.yml: $($detectedVersions.Haproxy)" "INFO" "Green"
        break
      }
    }
  }

  return $detectedVersions
}

# Check if Docker image exists
function Test-DockerImage {
  param([string]$ImageName)

  try {
    $result = docker images --format "{{.Repository}}:{{.Tag}}" | Where-Object { $_ -eq $ImageName }
    return $result -eq $ImageName
  }
  catch {
    return $false
  }
}

# Main program
try {
  Write-Log "=== Elf-Nginx Docker Image Push Script ===" "INFO" "Yellow"
  Write-Log "Execution time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO" "Gray"

  # Check Docker status
  Test-DockerRunning

  # Version handling
  if ($AutoDetectVersion) {
    $detectedVersions = Get-AutoDetectedVersions
    if ($detectedVersions.Nginx -and -not $NginxVersion) {
      $NginxVersion = $detectedVersions.Nginx
    }
    if ($detectedVersions.Haproxy -and -not $HaproxyVersion) {
      $HaproxyVersion = $detectedVersions.Haproxy
    }
  }

  # Use defaults if not specified and not auto-detected
  if (-not $NginxVersion) {
    $NginxVersion = "1.29.3"
    Write-Log "Using default Nginx version: $NginxVersion" "WARN" "Yellow"
  }
  if (-not $HaproxyVersion) {
    $HaproxyVersion = "3.3.0"
    Write-Log "Using default HAProxy version: $HaproxyVersion" "WARN" "Yellow"
  }

  Write-Log "=== Versions ===" "INFO" "Cyan"
  Write-Log "Nginx version: $NginxVersion" "INFO" "White"
  Write-Log "HAProxy version: $HaproxyVersion" "INFO" "White"
  Write-Log "================" "INFO" "Cyan"

  # Build full image names
  $nginxImageFull = "${nginxImageBase}:${NginxVersion}"
  $nginxImageLatest = "${nginxImageBase}:latest"
  $haproxyImageFull = "${haproxyImageBase}:${HaproxyVersion}"
  $haproxyImageLatest = "${haproxyImageBase}:latest"

  Write-Log "=== Image Validation ===" "INFO" "Cyan"

  # Validate image existence
  $validationErrors = @()

  if (-not $SkipNginx) {
    if (Test-DockerImage $nginxImageFull) {
      Write-Log "OK Nginx image exists: $nginxImageFull" "INFO" "Green"
    } else {
      $validationErrors += "Nginx image not found: $nginxImageFull"
      Write-Log "FAIL Nginx image not found: $nginxImageFull" "ERROR" "Red"
    }
  }

  if (-not $SkipHaproxy) {
    if (Test-DockerImage $haproxyImageFull) {
      Write-Log "OK HAProxy image exists: $haproxyImageFull" "INFO" "Green"
    } else {
      $validationErrors += "HAProxy image not found: $haproxyImageFull"
      Write-Log "FAIL HAProxy image not found: $haproxyImageFull" "ERROR" "Red"
    }
  }

  if ($validationErrors.Count -gt 0) {
    Write-Log "Image validation failed. Please build images first:" "ERROR" "Red"
    $validationErrors | ForEach-Object { Write-Log "  - $_" "ERROR" "Red" }
    Write-Log "Use this command to build images:" "INFO" "Yellow"
    Write-Log "  docker compose -f docker-compose.build.yml build" "INFO" "Gray"
    exit 1
  }

  Write-Log "OK All images validated" "INFO" "Green"

  if ($ValidateOnly) {
    Write-Log "Validate-only mode, skipping push" "INFO" "Yellow"
    exit 0
  }

  Write-Log "=== Pushing Images ===" "INFO" "Cyan"

  # Push Nginx images
  if (-not $SkipNginx) {
    Write-Log "Tagging Nginx image..." "INFO" "Cyan"
    docker tag $nginxImageFull $nginxImageLatest
    Write-Log "OK Tagged: $nginxImageFull -> $nginxImageLatest" "INFO" "Green"

    Write-Log "Pushing Nginx image tags: $NginxVersion, latest" "INFO" "Green"
    Write-Host "Pushing: $nginxImageFull ..." -NoNewline
    docker push $nginxImageFull
    Write-Host " Done!" -ForegroundColor Green

    Write-Host "Pushing: $nginxImageLatest ..." -NoNewline
    docker push $nginxImageLatest
    Write-Host " Done!" -ForegroundColor Green
  }

  # Push HAProxy images
  if (-not $SkipHaproxy) {
    Write-Log "Tagging HAProxy image..." "INFO" "Cyan"
    docker tag $haproxyImageFull $haproxyImageLatest
    Write-Log "OK Tagged: $haproxyImageFull -> $haproxyImageLatest" "INFO" "Green"

    Write-Log "Pushing HAProxy image tags: $HaproxyVersion, latest" "INFO" "Green"
    Write-Host "Pushing: $haproxyImageFull ..." -NoNewline
    docker push $haproxyImageFull
    Write-Host " Done!" -ForegroundColor Green

    Write-Host "Pushing: $haproxyImageLatest ..." -NoNewline
    docker push $haproxyImageLatest
    Write-Host " Done!" -ForegroundColor Green
  }

  Write-Log "=== Push Complete ===" "INFO" "Yellow"
  Write-Log "All images pushed to Docker Hub successfully" "INFO" "Green"
  Write-Log "Completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO" "Gray"

} catch {
  Write-Log "Error occurred: $($_.Exception.Message)" "ERROR" "Red"
  Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR" "Red"
  exit 1
}
