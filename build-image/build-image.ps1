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
$LATEST_IMAGE = "${IMAGE_NAME}:latest"
$WEB_IMAGE = "${IMAGE_NAME}-web:${IMAGE_VERSION}"
$WEB_LATEST_IMAGE = "${IMAGE_NAME}-web:latest"

Write-Host "" 
Write-Host "[BUILD] Will build and push:" -ForegroundColor Cyan
Write-Host "   - $FULL_IMAGE" -ForegroundColor White
Write-Host "   - $LATEST_IMAGE" -ForegroundColor White
Write-Host "   - $WEB_IMAGE" -ForegroundColor White
Write-Host "   - $WEB_LATEST_IMAGE" -ForegroundColor White
Write-Host ""

# Determine target platform (default to linux/amd64 for Swarm nodes)
$TargetPlatform = $env:TARGET_PLATFORM
if ([string]::IsNullOrWhiteSpace($TargetPlatform)) {
    $TargetPlatform = "linux/amd64"
}

Write-Host "Target platform: $TargetPlatform" -ForegroundColor Cyan
Write-Host ""

$useBuildx = $false
try {
    docker buildx version | Out-Null
    if ($LASTEXITCODE -eq 0) { $useBuildx = $true }
} catch {
    $useBuildx = $false
}

$BuildxPushed = $false
$BuilderName = $env:BUILDX_BUILDER_NAME
if ([string]::IsNullOrWhiteSpace($BuilderName)) {
    $BuilderName = "server-info-watchdog-builder"
}

if ($useBuildx) {
    $inspectOutput = docker buildx inspect $BuilderName 2>$null
    if ($LASTEXITCODE -eq 0) {
        if ($inspectOutput -notmatch "Driver:\s+docker-container") {
            docker buildx rm $BuilderName 2>$null | Out-Null
            docker buildx create --name $BuilderName --driver docker-container --use | Out-Null
        } else {
            docker buildx use $BuilderName | Out-Null
        }
    } else {
        docker buildx create --name $BuilderName --driver docker-container --use | Out-Null
    }

    docker buildx inspect --bootstrap | Out-Null
}

if ($useBuildx) {
    Write-Host "[BUILD] Using docker buildx for platform $TargetPlatform..." -ForegroundColor Cyan
    if ($FULL_IMAGE -ne $LATEST_IMAGE) {
        docker buildx build --platform $TargetPlatform -t $FULL_IMAGE -t $LATEST_IMAGE --provenance=false --push .
    } else {
        docker buildx build --platform $TargetPlatform -t $FULL_IMAGE --provenance=false --push .
    }
    $BuildxPushed = $true
} else {
    Write-Host "[BUILD] docker buildx not found, falling back to docker build (host architecture)..." -ForegroundColor Yellow
    docker build -t $FULL_IMAGE .
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Main image build failed" -ForegroundColor Red
    exit 1
}

# Build web image
Write-Host ""
Write-Host "[BUILD] Building web image..." -ForegroundColor Cyan

if ($useBuildx) {
    Write-Host "[BUILD] Using docker buildx for platform $TargetPlatform..." -ForegroundColor Cyan
    if ($WEB_IMAGE -ne $WEB_LATEST_IMAGE) {
        docker buildx build --platform $TargetPlatform -f Dockerfile_web -t $WEB_IMAGE -t $WEB_LATEST_IMAGE --build-arg "IMAGE_TAG=$IMAGE_VERSION" --provenance=false --push .
    } else {
        docker buildx build --platform $TargetPlatform -f Dockerfile_web -t $WEB_IMAGE --build-arg "IMAGE_TAG=$IMAGE_VERSION" --provenance=false --push .
    }
    $BuildxPushed = $true
} else {
    Write-Host "[BUILD] docker buildx not found, falling back to docker build (host architecture)..." -ForegroundColor Yellow
    docker build -f Dockerfile_web -t $WEB_IMAGE --build-arg "IMAGE_TAG=$IMAGE_VERSION" .
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Web image build failed" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[OK] Images built successfully:" -ForegroundColor Green
Write-Host "   - $FULL_IMAGE" -ForegroundColor White
Write-Host "   - $WEB_IMAGE" -ForegroundColor White
Write-Host ""

if ($BuildxPushed) {
    Write-Host "[OK] Images pushed successfully via buildx" -ForegroundColor Green
} else {
    Write-Host "" 
    Write-Host "[PUSH] Pushing to registry..." -ForegroundColor Cyan
    
    # Push main images
    Write-Host "[PUSH] Pushing: $FULL_IMAGE" -ForegroundColor Cyan
    docker push $FULL_IMAGE

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to push image: $FULL_IMAGE" -ForegroundColor Red
        Write-Host "        Please run 'docker login' for your registry and re-run the script." -ForegroundColor Yellow
        exit 1
    }

    Write-Host "[OK] Pushed: $FULL_IMAGE" -ForegroundColor Green

    if ($IMAGE_VERSION -ne "latest") {
        docker tag $FULL_IMAGE $LATEST_IMAGE
        docker push $LATEST_IMAGE
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Also pushed: $LATEST_IMAGE" -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Failed to push $LATEST_IMAGE" -ForegroundColor Red
            exit 1
        }
    }
    
    # Push web images
    Write-Host "[PUSH] Pushing: $WEB_IMAGE" -ForegroundColor Cyan
    docker push $WEB_IMAGE

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to push image: $WEB_IMAGE" -ForegroundColor Red
        exit 1
    }

    Write-Host "[OK] Pushed: $WEB_IMAGE" -ForegroundColor Green

    if ($IMAGE_VERSION -ne "latest") {
        docker tag $WEB_IMAGE $WEB_LATEST_IMAGE
        docker push $WEB_LATEST_IMAGE
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Also pushed: $WEB_LATEST_IMAGE" -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Failed to push $WEB_LATEST_IMAGE" -ForegroundColor Red
            exit 1
        }
    }
    
    Write-Host "[OK] All images pushed successfully" -ForegroundColor Green
}
    
    # Update .env with new version
    if (Test-Path .env) {
        $envLines = Get-Content .env -ErrorAction SilentlyContinue
        
        $hasImageName = $false
        $hasImageVersion = $false
        $hasWebImageVersion = $false
        $newLines = @()
        
        foreach ($line in $envLines) {
            if ($line -match '^IMAGE_NAME=') {
                $newLines += "IMAGE_NAME=$IMAGE_NAME"
                $hasImageName = $true
            } elseif ($line -match '^IMAGE_VERSION=') {
                $newLines += "IMAGE_VERSION=$IMAGE_VERSION"
                $hasImageVersion = $true
            } elseif ($line -match '^WEB_IMAGE_VERSION=') {
                $newLines += "WEB_IMAGE_VERSION=$IMAGE_VERSION"
                $hasWebImageVersion = $true
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
        if (-not $hasWebImageVersion) {
            $newLines += "WEB_IMAGE_VERSION=$IMAGE_VERSION"
        }
        
        $newLines | Set-Content .env -Encoding utf8
        Write-Host "[OK] Updated .env with IMAGE_NAME=$IMAGE_NAME, IMAGE_VERSION=$IMAGE_VERSION, WEB_IMAGE_VERSION=$IMAGE_VERSION" -ForegroundColor Green
    }
} else {
    Write-Host "[ERROR] Build failed" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[DONE] Build complete!" -ForegroundColor Green
