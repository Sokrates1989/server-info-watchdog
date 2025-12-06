# build-image.ps1
# Build and push the Server Info Watchdog Docker image

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
Set-Location $ProjectRoot

Write-Host "Server Info Watchdog - Build Production Image" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# Read current values from .env
$IMAGE_NAME = "sokrates1989/server-info-watchdog"
$IMAGE_VERSION = "latest"

if (Test-Path .env) {
    $envContent = Get-Content .env -ErrorAction SilentlyContinue
    
    $nameLine = $envContent | Where-Object { $_ -match "^IMAGE_NAME=" }
    if ($nameLine) {
        $IMAGE_NAME = ($nameLine -split "=", 2)[1].Trim().Trim('"')
    }
    
    $versionLine = $envContent | Where-Object { $_ -match "^IMAGE_VERSION=" }
    if ($versionLine) {
        $IMAGE_VERSION = ($versionLine -split "=", 2)[1].Trim().Trim('"')
    }
}

# Prompt for image name
$inputName = Read-Host "Docker image name [$IMAGE_NAME]"
if (-not [string]::IsNullOrWhiteSpace($inputName)) {
    $IMAGE_NAME = $inputName
}

if ([string]::IsNullOrWhiteSpace($IMAGE_NAME)) {
    Write-Host "[ERROR] Image name is required" -ForegroundColor Red
    exit 1
}

# Prompt for version
$inputVersion = Read-Host "Image version [$IMAGE_VERSION]"
if (-not [string]::IsNullOrWhiteSpace($inputVersion)) {
    $IMAGE_VERSION = $inputVersion
}

if ([string]::IsNullOrWhiteSpace($IMAGE_VERSION)) {
    $IMAGE_VERSION = "latest"
}

$FULL_IMAGE = "${IMAGE_NAME}:${IMAGE_VERSION}"

Write-Host ""
Write-Host "[BUILD] Building: $FULL_IMAGE" -ForegroundColor Cyan
Write-Host ""

# Build the image
docker build -t $FULL_IMAGE .

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "[OK] Image built successfully: $FULL_IMAGE" -ForegroundColor Green
    Write-Host ""
    
    # Ask about pushing
    $pushImage = Read-Host "Push to registry? (y/N)"
    if ($pushImage -match "^[Yy]$") {
        Write-Host ""
        Write-Host "[PUSH] Pushing to registry..." -ForegroundColor Cyan
        docker push $FULL_IMAGE
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Image pushed successfully" -ForegroundColor Green
            
            # Also tag and push as latest if version is not latest
            if ($IMAGE_VERSION -ne "latest") {
                $pushLatest = Read-Host "Also push as 'latest'? (y/N)"
                if ($pushLatest -match "^[Yy]$") {
                    docker tag $FULL_IMAGE "${IMAGE_NAME}:latest"
                    docker push "${IMAGE_NAME}:latest"
                    Write-Host "[OK] Also pushed as ${IMAGE_NAME}:latest" -ForegroundColor Green
                }
            }
        } else {
            Write-Host "[ERROR] Failed to push image" -ForegroundColor Red
            exit 1
        }
    }
    
    # Update .env with new version
    if (Test-Path .env) {
        $envLines = Get-Content .env -ErrorAction SilentlyContinue
        
        $hasImageName = $false
        $hasImageVersion = $false
        $newLines = @()
        
        foreach ($line in $envLines) {
            if ($line -match '^IMAGE_NAME=') {
                $newLines += "IMAGE_NAME=$IMAGE_NAME"
                $hasImageName = $true
            } elseif ($line -match '^IMAGE_VERSION=') {
                $newLines += "IMAGE_VERSION=$IMAGE_VERSION"
                $hasImageVersion = $true
            } else {
                $newLines += $line
            }
        }
        
        if (-not $hasImageName) {
            $newLines += "IMAGE_NAME=$IMAGE_NAME"
        }
        if (-not $hasImageVersion) {
            $newLines += "IMAGE_VERSION=$IMAGE_VERSION"
        }
        
        $newLines | Set-Content .env -Encoding utf8
        Write-Host "[OK] Updated .env with IMAGE_NAME=$IMAGE_NAME, IMAGE_VERSION=$IMAGE_VERSION" -ForegroundColor Green
    }
} else {
    Write-Host "[ERROR] Build failed" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[DONE] Build complete!" -ForegroundColor Green
