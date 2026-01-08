# =============================================================================
# Build and push Docker image for Server Info Watchdog Web UI
# =============================================================================

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# Default values
$IMAGE_NAME = if ($env:IMAGE_NAME) { $env:IMAGE_NAME } else { "sokrates1989/server-info-watchdog-web" }
$CI_ENV_FILE = Join-Path $ProjectRoot ".ci.env"

# Load version from .ci.env if it exists
$IMAGE_VERSION = "latest"
if (Test-Path $CI_ENV_FILE) {
    $envContent = Get-Content $CI_ENV_FILE
    foreach ($line in $envContent) {
        if ($line -match "^IMAGE_VERSION=(.+)$") {
            $IMAGE_VERSION = $Matches[1].Trim()
        }
    }
}

Write-Host "=============================================" -ForegroundColor Green
Write-Host "Server Info Watchdog Web UI - Image Builder" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""

# Prompt for version
$inputVersion = Read-Host "Enter image version [$IMAGE_VERSION]"
if ($inputVersion) {
    $IMAGE_VERSION = $inputVersion
}

Write-Host ""
Write-Host "Building: " -NoNewline
Write-Host "${IMAGE_NAME}:${IMAGE_VERSION}" -ForegroundColor Yellow
Write-Host ""

# Build the image
Set-Location $ProjectRoot

docker build `
    -f Dockerfile_web `
    --build-arg IMAGE_TAG="$IMAGE_VERSION" `
    -t "${IMAGE_NAME}:${IMAGE_VERSION}" `
    -t "${IMAGE_NAME}:latest" `
    .

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Build complete!" -ForegroundColor Green
Write-Host ""

# Ask about pushing
if ($env:SKIP_PUSH -eq "true") {
    Write-Host "Skipping push (SKIP_PUSH=true)" -ForegroundColor Yellow
    exit 0
}

$pushConfirm = Read-Host "Push image to registry? [y/N]"
if ($pushConfirm -match "^[Yy]$") {
    Write-Host ""
    Write-Host "Pushing ${IMAGE_NAME}:${IMAGE_VERSION}..."
    
    # Push version tag
    docker push "${IMAGE_NAME}:${IMAGE_VERSION}"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Push failed. Attempting docker login..." -ForegroundColor Red
        docker login
        docker push "${IMAGE_NAME}:${IMAGE_VERSION}"
    }
    
    # Push latest tag
    docker push "${IMAGE_NAME}:latest"
    if ($LASTEXITCODE -ne 0) {
        docker login
        docker push "${IMAGE_NAME}:latest"
    }
    
    Write-Host ""
    Write-Host "Push complete!" -ForegroundColor Green
}

# Update .ci.env with new version
if (Test-Path $CI_ENV_FILE) {
    $content = Get-Content $CI_ENV_FILE -Raw
    if ($content -match "IMAGE_VERSION=") {
        $content = $content -replace "IMAGE_VERSION=.+", "IMAGE_VERSION=$IMAGE_VERSION"
    } else {
        $content += "`nIMAGE_VERSION=$IMAGE_VERSION"
    }
    Set-Content -Path $CI_ENV_FILE -Value $content.TrimEnd()
    Write-Host "Updated .ci.env with IMAGE_VERSION=$IMAGE_VERSION" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
