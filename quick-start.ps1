# quick-start.ps1
# Quick start tool for Server Info Watchdog

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$setupDir = Join-Path $scriptDir "setup"

# Import modules
Import-Module "$setupDir\modules\docker_helpers.ps1" -Force
Import-Module "$setupDir\modules\browser_helpers.ps1" -Force
Import-Module "$setupDir\modules\menu_handlers.ps1" -Force

Write-Host "Server Info Watchdog - Quick Start" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""

# Check Docker availability
if (-not (Test-DockerInstallation)) {
    exit 1
}
Write-Host ""

# Check if .env exists
if (-not (Test-Path .env)) {
    Write-Host "[WARN] .env file not found" -ForegroundColor Yellow
    Write-Host ""
    if (Test-Path setup\.env.template) {
        $createEnv = Read-Host "Create .env from template? (Y/n)"
        if ($createEnv -ne "n" -and $createEnv -ne "N") {
            Copy-Item setup\.env.template .env
            Write-Host "[OK] .env created from template" -ForegroundColor Green
            Write-Host "[WARN] Please edit .env with your configuration before continuing" -ForegroundColor Yellow
            Write-Host ""
            $editor = $env:EDITOR
            if ([string]::IsNullOrWhiteSpace($editor)) { $editor = "notepad" }
            $openNow = Read-Host "Open .env now in $editor? (Y/n)"
            if ($openNow -notmatch "^[Nn]$") {
                & $editor ".env"
            }
            $null = Read-Host "Press Enter to continue after editing .env..."
        } else {
            Write-Host "[ERROR] Cannot continue without .env file" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "[ERROR] setup\.env.template not found!" -ForegroundColor Red
        exit 1
    }
    Write-Host ""
}

# Determine compose file
$COMPOSE_FILE = "local-deployment\docker-compose.yml"

if (-not (Test-Path $COMPOSE_FILE)) {
    Write-Host "[WARN] $COMPOSE_FILE not found" -ForegroundColor Yellow
    # Fall back to old location
    if (Test-Path "docker-compose.yml") {
        $COMPOSE_FILE = "docker-compose.yml"
        Write-Host "   Using fallback: $COMPOSE_FILE" -ForegroundColor Gray
    }
}

Write-Host "Using compose file: $COMPOSE_FILE" -ForegroundColor Cyan
Write-Host ""

# Show main menu
Show-MainMenu -ComposeFile $COMPOSE_FILE
