<#
.SYNOPSIS
    Keycloak operations module for Server Info Watchdog quick-start menu.

.DESCRIPTION
    This module provides functions for Keycloak-related operations including
    bootstrap, token retrieval, and realm management for Server Info Watchdog.

.NOTES
    Author: Auto-generated
    Version: 1.0.0
#>

function Get-EnvVariable {
    <#
    .SYNOPSIS
        Get an environment variable from .env file or environment.

    .PARAMETER VariableName
        Name of the variable to retrieve.

    .PARAMETER EnvFile
        Path to the .env file.

    .PARAMETER DefaultValue
        Default value if not found.

    .RETURNS
        The variable value or default.
    #>
    param(
        [string]$VariableName,
        [string]$EnvFile = ".env",
        [string]$DefaultValue = ""
    )

    $value = $DefaultValue

    if (Test-Path $EnvFile) {
        $envContent = Get-Content $EnvFile -ErrorAction SilentlyContinue
        $line = $envContent | Where-Object { $_ -match "^$VariableName=" }
        if ($line) {
            $value = ($line -split "=", 2)[1].Trim().Trim('"')
        }
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
        $envValue = [Environment]::GetEnvironmentVariable($VariableName)
        if (-not [string]::IsNullOrWhiteSpace($envValue)) {
            $value = $envValue
        }
    }

    return $value
}

function Invoke-KeycloakBootstrap {
    <#
    .SYNOPSIS
        Bootstrap Keycloak realm, clients, roles, and users for Server Info Watchdog.

    .DESCRIPTION
        This function:
        - Checks if Keycloak is reachable
        - Collects configuration from user
        - Creates realm, clients, roles, and users

    .RETURNS
        0 on success, 1 on failure.
    #>

    $projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
    
    Write-Host ""
    Write-Host "[KEYCLOAK] Keycloak Bootstrap for Server Info Watchdog" -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Load .env defaults
    $keycloakUrl = Get-EnvVariable -VariableName "KEYCLOAK_URL" -EnvFile "$projectRoot\.env" -DefaultValue "http://localhost:9090"
    $keycloakRealm = Get-EnvVariable -VariableName "KEYCLOAK_REALM" -EnvFile "$projectRoot\.env" -DefaultValue "watchdog"
    $webPort = Get-EnvVariable -VariableName "WEB_PORT" -EnvFile "$projectRoot\.env" -DefaultValue "8080"
    $apiPort = Get-EnvVariable -VariableName "ADMIN_API_PORT" -EnvFile "$projectRoot\.env" -DefaultValue "5000"
    
    # Check if Keycloak is reachable
    Write-Host "[CHECK] Checking Keycloak at $keycloakUrl..." -ForegroundColor Cyan
    try {
        $null = Invoke-WebRequest -Uri "$keycloakUrl/" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
        Write-Host "[OK] Keycloak is reachable" -ForegroundColor Green
    } catch {
        Write-Host ""
        Write-Host "[ERROR] Cannot reach Keycloak at $keycloakUrl" -ForegroundColor Red
        Write-Host ""
        Write-Host "Please ensure Keycloak is running. Start it from the dedicated repo:" -ForegroundColor Yellow
        Write-Host "  https://github.com/Sokrates1989/keycloak.git" -ForegroundColor Gray
        Write-Host ""
        return 1
    }
    Write-Host ""
    
    # Collect configuration
    $inputUrl = Read-Host "Keycloak base URL [$keycloakUrl]"
    if (-not [string]::IsNullOrWhiteSpace($inputUrl)) {
        $keycloakUrl = $inputUrl
    }
    
    $adminUser = Read-Host "Keycloak admin username [admin]"
    if ([string]::IsNullOrWhiteSpace($adminUser)) {
        $adminUser = "admin"
    }
    
    $adminPassword = Read-Host "Keycloak admin password [admin]"
    if ([string]::IsNullOrWhiteSpace($adminPassword)) {
        $adminPassword = "admin"
    }
    
    $realm = Read-Host "Realm name [$keycloakRealm]"
    if ([string]::IsNullOrWhiteSpace($realm)) {
        $realm = $keycloakRealm
    }
    
    $frontendClient = Read-Host "Frontend client ID [watchdog-frontend]"
    if ([string]::IsNullOrWhiteSpace($frontendClient)) {
        $frontendClient = "watchdog-frontend"
    }
    
    $backendClient = Read-Host "Backend client ID [watchdog-backend]"
    if ([string]::IsNullOrWhiteSpace($backendClient)) {
        $backendClient = "watchdog-backend"
    }
    
    $frontendUrl = Read-Host "Frontend root URL [http://localhost:$webPort]"
    if ([string]::IsNullOrWhiteSpace($frontendUrl)) {
        $frontendUrl = "http://localhost:$webPort"
    }
    
    $apiUrl = Read-Host "API root URL [http://localhost:$apiPort]"
    if ([string]::IsNullOrWhiteSpace($apiUrl)) {
        $apiUrl = "http://localhost:$apiPort"
    }
    
    Write-Host ""
    Write-Host "[INFO] Creating roles:" -ForegroundColor Cyan
    Write-Host "   - watchdog:admin (full access)" -ForegroundColor Gray
    Write-Host "   - watchdog:read  (view-only access)" -ForegroundColor Gray
    Write-Host ""
    
    $createAdmin = Read-Host "Create default admin user? (Y/n)"
    $adminUsername = ""
    $adminUserpass = ""
    
    if ($createAdmin -notmatch "^[Nn]$") {
        $adminUsername = Read-Host "Admin username [admin]"
        if ([string]::IsNullOrWhiteSpace($adminUsername)) {
            $adminUsername = "admin"
        }
        
        $adminUserpass = Read-Host "Admin password [admin]"
        if ([string]::IsNullOrWhiteSpace($adminUserpass)) {
            $adminUserpass = "admin"
        }
    }
    
    Write-Host ""
    Write-Host "[RUN] Bootstrapping Keycloak realm..." -ForegroundColor Cyan
    Write-Host ""
    
    # Build arguments
    $bootstrapScript = Join-Path $projectRoot "scripts\keycloak_bootstrap.py"
    
    if (-not (Test-Path $bootstrapScript)) {
        Write-Host "[ERROR] Bootstrap script not found at $bootstrapScript" -ForegroundColor Red
        return 1
    }
    
    # Try Python first, fallback to Docker
    $useDocker = $false
    $pythonCmd = $null
    
    # Check if Python is available
    if (Get-Command python -ErrorAction SilentlyContinue) {
        $pythonCmd = "python"
    } elseif (Get-Command python3 -ErrorAction SilentlyContinue) {
        $pythonCmd = "python3"
    } else {
        Write-Host "[WARN] Python is not available. Using Docker fallback..." -ForegroundColor Yellow
        $useDocker = $true
    }
    
    if (-not $useDocker) {
        # Test Python command works
        try {
            & $pythonCmd --version 2>$null
            if ($LASTEXITCODE -ne 0) {
                throw "Python command failed"
            }
        } catch {
            Write-Host "[WARN] Python command '$pythonCmd' is not working properly. Using Docker fallback..." -ForegroundColor Yellow
            $useDocker = $true
        }
    }
    
    if (-not $useDocker) {
        # Install requests if needed
        try {
            & $pythonCmd -c "import requests" 2>$null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[INFO] Installing requests module..." -ForegroundColor Yellow
                & $pythonCmd -m pip install requests --quiet
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to install requests"
                }
            }
        } catch {
            Write-Host "[WARN] Failed to install requests module. Using Docker fallback..." -ForegroundColor Yellow
            $useDocker = $true
        }
    }
    
    # Try Python script if not using Docker
    if (-not $useDocker) {
        # Build command arguments
        $args = @(
            $bootstrapScript,
            "--base-url", $keycloakUrl,
            "--admin-user", $adminUser,
            "--admin-password", $adminPassword,
            "--realm", $realm,
            "--frontend-client-id", $frontendClient,
            "--backend-client-id", $backendClient,
            "--frontend-root-url", $frontendUrl,
            "--api-root-url", $apiUrl
        )
        
        if (-not [string]::IsNullOrWhiteSpace($adminUsername)) {
            $args += @("--user", "${adminUsername}:${adminUserpass}:watchdog:admin")
        }
        
        # Run the bootstrap script
        try {
            & $pythonCmd @args
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) {
                throw "Bootstrap script failed"
            }
        } catch {
            Write-Host "[WARN] Failed to run bootstrap script. Using Docker fallback..." -ForegroundColor Yellow
            $useDocker = $true
        }
    }
    
    # Docker fallback if needed
    if ($useDocker) {
        Write-Host ""
        Write-Host "[DOCKER] Using Docker fallback for Keycloak bootstrap..." -ForegroundColor Cyan
        Write-Host ""
        
        # Create Dockerfile if needed
        $dockerfilePath = Join-Path $projectRoot "scripts\Dockerfile"
        if (-not (Test-Path $dockerfilePath)) {
            Write-Host "[INFO] Creating Dockerfile for bootstrap..." -ForegroundColor Cyan
            @"
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY keycloak_bootstrap.py .
CMD ["python", "keycloak_bootstrap.py"]
"@ | Out-File -FilePath $dockerfilePath -Encoding utf8
        }
        
        # Build image
        Write-Host "[BUILD] Building bootstrap image..." -ForegroundColor Cyan
        $buildResult = docker build -t server-info-watchdog-bootstrap "$projectRoot\scripts" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] Failed to build bootstrap Docker image" -ForegroundColor Red
            Write-Host $buildResult -ForegroundColor Gray
            return 1
        }
        
        # Run bootstrap with Docker
        Write-Host "[RUN] Running bootstrap in Docker container..." -ForegroundColor Cyan
        $dockerArgs = @(
            "run", "--rm", "-it", "--network", "host",
            "-e", "KEYCLOAK_URL=$keycloakUrl",
            "-e", "KEYCLOAK_ADMIN_USER=$adminUser",
            "-e", "KEYCLOAK_ADMIN_PASSWORD=$adminPassword",
            "-e", "REALM=$realm",
            "-e", "FRONTEND_CLIENT_ID=$frontendClient",
            "-e", "BACKEND_CLIENT_ID=$backendClient",
            "-e", "FRONTEND_ROOT_URL=$frontendUrl",
            "-e", "API_ROOT_URL=$apiUrl"
        )
        
        if (-not [string]::IsNullOrWhiteSpace($adminUsername)) {
            $dockerArgs += @("-e", "USER_SPEC=${adminUsername}:${adminUserpass}:watchdog:admin")
        }
        
        $dockerArgs += "server-info-watchdog-bootstrap"
        
        $dockerResult = docker @dockerArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] Docker bootstrap failed" -ForegroundColor Red
            Write-Host $dockerResult -ForegroundColor Gray
            return 1
        }
    }
    
    # Success message (both Python and Docker paths lead here)
    Write-Host ""
    Write-Host "[OK] Keycloak bootstrap completed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "[INFO] Next steps:" -ForegroundColor Cyan
    Write-Host "   1. Copy the backend_client_secret from above" -ForegroundColor Gray
    Write-Host "   2. Update your .env file with:" -ForegroundColor Gray
    Write-Host "      KEYCLOAK_ENABLED=true" -ForegroundColor Gray
    Write-Host "      KEYCLOAK_URL=$keycloakUrl" -ForegroundColor Gray
    Write-Host "      KEYCLOAK_REALM=$realm" -ForegroundColor Gray
    Write-Host "      KEYCLOAK_CLIENT_ID=$backendClient" -ForegroundColor Gray
    Write-Host "      KEYCLOAK_CLIENT_ID_WEB=$frontendClient" -ForegroundColor Gray
    Write-Host "      KEYCLOAK_CLIENT_SECRET=<paste_secret_here>" -ForegroundColor Gray
    Write-Host ""
    
    $updateEnv = Read-Host "Update .env with Keycloak settings now? (Y/n)"
    if ($updateEnv -notmatch "^[Nn]$") {
        Update-EnvKeycloakSettings -EnvFile "$projectRoot\.env" -KeycloakUrl $keycloakUrl -Realm $realm -BackendClient $backendClient -FrontendClient $frontendClient
    }
    
    return 0
}

function Update-EnvKeycloakSettings {
    <#
    .SYNOPSIS
        Update .env file with Keycloak settings.
    #>
    param(
        [string]$EnvFile,
        [string]$KeycloakUrl,
        [string]$Realm,
        [string]$BackendClient,
        [string]$FrontendClient
    )
    
    if (-not (Test-Path $EnvFile)) {
        Write-Host "[ERROR] .env file not found at $EnvFile" -ForegroundColor Red
        return
    }
    
    $settings = @{
        "KEYCLOAK_ENABLED" = "true"
        "KEYCLOAK_URL" = $KeycloakUrl
        "KEYCLOAK_INTERNAL_URL" = "http://host.docker.internal:$($KeycloakUrl.Split(':')[2])"
        "KEYCLOAK_REALM" = $Realm
        "KEYCLOAK_CLIENT_ID" = $BackendClient
        "KEYCLOAK_CLIENT_ID_WEB" = $FrontendClient
    }
    
    $content = Get-Content $EnvFile -Raw
    
    foreach ($key in $settings.Keys) {
        $value = $settings[$key]
        if ($content -match "(?m)^${key}=") {
            $content = $content -replace "(?m)^${key}=.*", "${key}=${value}"
        } else {
            $content = $content.TrimEnd() + "`n${key}=${value}`n"
        }
    }
    
    Set-Content -Path $EnvFile -Value $content.TrimEnd()
    
    Write-Host "[OK] Updated .env with Keycloak settings" -ForegroundColor Green
    Write-Host ""
    Write-Host "[WARN] Don't forget to set KEYCLOAK_CLIENT_SECRET in .env!" -ForegroundColor Yellow
    
    $clientSecret = Read-Host -AsSecureString "Enter client secret to save to .env (or press Enter to skip)"
    if (-not [string]::IsNullOrWhiteSpace($clientSecret)) {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($clientSecret)
        $clientSecretPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        
        $content = Get-Content $EnvFile -Raw
        if ($content -match "(?m)^KEYCLOAK_CLIENT_SECRET=") {
            $content = $content -replace "(?m)^KEYCLOAK_CLIENT_SECRET=.*", "KEYCLOAK_CLIENT_SECRET=${clientSecretPlain}"
        } else {
            $content = $content.TrimEnd() + "`nKEYCLOAK_CLIENT_SECRET=${clientSecretPlain}`n"
        }
        Set-Content -Path $EnvFile -Value $content.TrimEnd()
        Write-Host "[OK] Client secret saved to .env" -ForegroundColor Green
    }
}
