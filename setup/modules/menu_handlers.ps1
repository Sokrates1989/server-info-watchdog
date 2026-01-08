# menu_handlers.ps1
# PowerShell module for handling menu actions

function Start-RunOnce {
    param([string]$ComposeFile)
    
    Write-Host "[RUN] Running watchdog check once..." -ForegroundColor Cyan
    Write-Host ""
    $oldComposeFile = $env:COMPOSE_FILE
    $env:COMPOSE_FILE = ""
    docker compose --env-file .env -f $ComposeFile run --rm --build watchdog python src/check_server.py
    $env:COMPOSE_FILE = $oldComposeFile
    Write-Host ""
    Write-Host "[OK] Check completed" -ForegroundColor Green
}

function Invoke-DockerComposeDown {
    param([string]$ComposeFile)
    
    Write-Host "[STOP] Stopping containers..." -ForegroundColor Yellow
    Write-Host "   Using compose file: $ComposeFile" -ForegroundColor Gray
    Write-Host ""
    $oldComposeFile = $env:COMPOSE_FILE
    $env:COMPOSE_FILE = ""
    docker compose --env-file .env -f $ComposeFile down --remove-orphans
    $env:COMPOSE_FILE = $oldComposeFile
    Write-Host ""
    Write-Host "[OK] Containers stopped" -ForegroundColor Green
}

function Build-ProductionImage {
    Write-Host "[BUILD] Building production Docker image..." -ForegroundColor Cyan
    Write-Host ""
    if (Test-Path "build-image\build-image.ps1") {
        & .\build-image\build-image.ps1
    } elseif (Test-Path "build-image\build-image.sh") {
        Write-Host "Running build-image.sh via bash..." -ForegroundColor Yellow
        bash build-image/build-image.sh
    } else {
        Write-Host "[ERROR] build-image script not found" -ForegroundColor Red
    }
}

function Build-WebImage {
    Write-Host "[BUILD] Building web UI Docker image..." -ForegroundColor Cyan
    Write-Host ""
    if (Test-Path "build-image\build-web-image.ps1") {
        & .\build-image\build-web-image.ps1
    } elseif (Test-Path "build-image\build-web-image.sh") {
        Write-Host "Running build-web-image.sh via bash..." -ForegroundColor Yellow
        bash build-image/build-web-image.sh
    } else {
        Write-Host "[ERROR] build-web-image script not found" -ForegroundColor Red
    }
}

function Start-WebUI {
    param([string]$ComposeFile)
    
    Write-Host "[WEB] Starting Web UI..." -ForegroundColor Cyan
    Write-Host "   This will start the admin API and web interface." -ForegroundColor Gray
    Write-Host ""
    $oldComposeFile = $env:COMPOSE_FILE
    $env:COMPOSE_FILE = ""
    docker compose --env-file .env -f $ComposeFile --profile web up -d --build
    $env:COMPOSE_FILE = $oldComposeFile
    Write-Host ""
    $webPort = if ($env:WEB_PORT) { $env:WEB_PORT } else { "8080" }
    Write-Host "[OK] Web UI started at http://localhost:$webPort" -ForegroundColor Green
    Write-Host "   Use WATCHDOG_ADMIN_TOKEN from .env to login." -ForegroundColor Gray
}

function Stop-WebUI {
    param([string]$ComposeFile)
    
    Write-Host "[STOP] Stopping Web UI..." -ForegroundColor Yellow
    $oldComposeFile = $env:COMPOSE_FILE
    $env:COMPOSE_FILE = ""
    docker compose --env-file .env -f $ComposeFile --profile web down
    $env:COMPOSE_FILE = $oldComposeFile
    Write-Host ""
    Write-Host "[OK] Web UI stopped" -ForegroundColor Green
}

function Show-Logs {
    param([string]$ComposeFile)
    
    Write-Host "[LOGS] Viewing logs..." -ForegroundColor Cyan
    $oldComposeFile = $env:COMPOSE_FILE
    $env:COMPOSE_FILE = ""
    docker compose --env-file .env -f $ComposeFile logs -f
    $env:COMPOSE_FILE = $oldComposeFile
}

function Show-MainMenu {
    param([string]$ComposeFile)

    $summary = $null
    $exitCode = 0

    $menuNext = 1
    $MENU_RUN_ONCE = $menuNext; $menuNext++

    $MENU_MONITOR_LOGS = $menuNext; $menuNext++

    $MENU_MAINT_DOWN = $menuNext; $menuNext++

    $MENU_BUILD_IMAGE = $menuNext; $menuNext++

    $MENU_START_WEB = $menuNext; $menuNext++
    $MENU_STOP_WEB = $menuNext; $menuNext++
    $MENU_BUILD_WEB = $menuNext; $menuNext++

    $MENU_EXIT = $menuNext

    Write-Host "" 
    Write-Host "================ Main Menu ================" -ForegroundColor Yellow
    Write-Host "" 
    Write-Host "Run:" -ForegroundColor Yellow
    Write-Host "  $MENU_RUN_ONCE) Run check once" -ForegroundColor Gray
    Write-Host "" 
    Write-Host "Monitoring:" -ForegroundColor Yellow
    Write-Host "  $MENU_MONITOR_LOGS) View logs" -ForegroundColor Gray
    Write-Host "" 
    Write-Host "Web UI:" -ForegroundColor Yellow
    Write-Host "  $MENU_START_WEB) Start Web UI (admin interface)" -ForegroundColor Gray
    Write-Host "  $MENU_STOP_WEB) Stop Web UI" -ForegroundColor Gray
    Write-Host "  $MENU_BUILD_WEB) Build Web UI Docker Image" -ForegroundColor Gray
    Write-Host "" 
    Write-Host "Maintenance:" -ForegroundColor Yellow
    Write-Host "  $MENU_MAINT_DOWN) Docker Compose Down (stop all containers)" -ForegroundColor Gray
    Write-Host "" 
    Write-Host "Build:" -ForegroundColor Yellow
    Write-Host "  $MENU_BUILD_IMAGE) Build Watchdog Docker Image" -ForegroundColor Gray
    Write-Host "" 
    Write-Host "  $MENU_EXIT) Exit" -ForegroundColor Gray
    Write-Host ""
    $choice = Read-Host "Your choice (1-$MENU_EXIT)"

    switch ($choice) {
        "$MENU_RUN_ONCE" {
            Start-RunOnce -ComposeFile $ComposeFile
            $summary = "Check executed"
        }
        "$MENU_MONITOR_LOGS" {
            Show-Logs -ComposeFile $ComposeFile
            $summary = "Logs viewed"
        }
        "$MENU_MAINT_DOWN" {
            Invoke-DockerComposeDown -ComposeFile $ComposeFile
            $summary = "Docker Compose Down executed"
        }
        "$MENU_BUILD_IMAGE" {
            Build-ProductionImage
            $summary = "Image build executed"
        }
        "$MENU_START_WEB" {
            Start-WebUI -ComposeFile $ComposeFile
            $summary = "Web UI started"
        }
        "$MENU_STOP_WEB" {
            Stop-WebUI -ComposeFile $ComposeFile
            $summary = "Web UI stopped"
        }
        "$MENU_BUILD_WEB" {
            Build-WebImage
            $summary = "Web image build executed"
        }
        "$MENU_EXIT" {
            Write-Host "Goodbye!" -ForegroundColor Cyan
            exit 0
        }
        Default {
            Write-Host "[ERROR] Invalid selection. Please re-run the script." -ForegroundColor Yellow
            exit 1
        }
    }

    Write-Host ""
    if ($summary) {
        Write-Host "[OK] $summary" -ForegroundColor Green
    }
    Write-Host "[INFO] Quick-start finished. Run again for more actions." -ForegroundColor Cyan
    Write-Host ""
    exit $exitCode
}
