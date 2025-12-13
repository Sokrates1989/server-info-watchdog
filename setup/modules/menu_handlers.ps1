# menu_handlers.ps1
# PowerShell module for handling menu actions

function Start-Watchdog {
    param([string]$ComposeFile)
    
    Write-Host "[START] Starting Server Info Watchdog..." -ForegroundColor Cyan
    Write-Host ""
    docker compose --env-file .env -f $ComposeFile up --build
}

function Start-WatchdogDetached {
    param([string]$ComposeFile)
    
    Write-Host "[START] Starting Server Info Watchdog (detached)..." -ForegroundColor Cyan
    Write-Host ""
    docker compose --env-file .env -f $ComposeFile up --build -d
    Write-Host ""
    Write-Host "[OK] Service started in background" -ForegroundColor Green
    Write-Host "View logs with: docker compose --env-file .env -f $ComposeFile logs -f" -ForegroundColor Gray
}

function Start-RunOnce {
    param([string]$ComposeFile)
    
    Write-Host "[RUN] Running watchdog check once..." -ForegroundColor Cyan
    Write-Host ""
    docker compose --env-file .env -f $ComposeFile run --rm watchdog python src/check_server.py
    Write-Host ""
    Write-Host "[OK] Check completed" -ForegroundColor Green
}

function Invoke-DockerComposeDown {
    param([string]$ComposeFile)
    
    Write-Host "[STOP] Stopping containers..." -ForegroundColor Yellow
    Write-Host "   Using compose file: $ComposeFile" -ForegroundColor Gray
    Write-Host ""
    docker compose --env-file .env -f $ComposeFile down
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

function Show-Logs {
    param([string]$ComposeFile)
    
    Write-Host "[LOGS] Viewing logs..." -ForegroundColor Cyan
    docker compose --env-file .env -f $ComposeFile logs -f
}

function Show-MainMenu {
    param([string]$ComposeFile)

    $summary = $null
    $exitCode = 0

    $menuNext = 1
    $MENU_RUN_START = $menuNext; $menuNext++
    $MENU_RUN_START_DETACHED = $menuNext; $menuNext++
    $MENU_RUN_ONCE = $menuNext; $menuNext++

    $MENU_MONITOR_LOGS = $menuNext; $menuNext++

    $MENU_MAINT_DOWN = $menuNext; $menuNext++

    $MENU_BUILD_IMAGE = $menuNext; $menuNext++

    $MENU_EXIT = $menuNext

    Write-Host "" 
    Write-Host "================ Main Menu ================" -ForegroundColor Yellow
    Write-Host "" 
    Write-Host "Run:" -ForegroundColor Yellow
    Write-Host "  $MENU_RUN_START) Start Watchdog (docker compose up)" -ForegroundColor Gray
    Write-Host "  $MENU_RUN_START_DETACHED) Start Watchdog detached (background)" -ForegroundColor Gray
    Write-Host "  $MENU_RUN_ONCE) Run check once" -ForegroundColor Gray
    Write-Host "" 
    Write-Host "Monitoring:" -ForegroundColor Yellow
    Write-Host "  $MENU_MONITOR_LOGS) View logs" -ForegroundColor Gray
    Write-Host "" 
    Write-Host "Maintenance:" -ForegroundColor Yellow
    Write-Host "  $MENU_MAINT_DOWN) Docker Compose Down (stop containers)" -ForegroundColor Gray
    Write-Host "" 
    Write-Host "Build:" -ForegroundColor Yellow
    Write-Host "  $MENU_BUILD_IMAGE) Build Production Docker Image" -ForegroundColor Gray
    Write-Host "" 
    Write-Host "  $MENU_EXIT) Exit" -ForegroundColor Gray
    Write-Host ""
    $choice = Read-Host "Your choice (1-$MENU_EXIT)"

    switch ($choice) {
        "$MENU_RUN_START" {
            Start-Watchdog -ComposeFile $ComposeFile
            $summary = "Watchdog started"
        }
        "$MENU_RUN_START_DETACHED" {
            Start-WatchdogDetached -ComposeFile $ComposeFile
            $summary = "Watchdog started in background"
        }
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
