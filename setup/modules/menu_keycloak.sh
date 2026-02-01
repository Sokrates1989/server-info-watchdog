#!/bin/bash
#
# menu_keycloak.sh
#
# Module for Keycloak-related menu actions for Server Info Watchdog.
# This script provides functions to bootstrap Keycloak realm, clients, and users.
#

# Get script directory
MENU_KEYCLOAK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read prompt helper (use parent if available)
if ! declare -f read_prompt >/dev/null 2>&1; then
    read_prompt() {
        local prompt="$1"
        local var_name="$2"
        if [[ -r /dev/tty ]]; then
            read -r -p "$prompt" "$var_name" < /dev/tty
        else
            read -r -p "$prompt" "$var_name"
        fi
    }
fi

# Handle Keycloak bootstrap for Server Info Watchdog.
#
# This function:
# - Checks if Keycloak is reachable
# - Collects configuration from user
# - Creates realm, clients, roles, and users
#
# Returns:
#   0 on success, 1 on failure.
handle_keycloak_bootstrap() {
    local project_root
    project_root="$(cd "${MENU_KEYCLOAK_DIR}/../.." && pwd)"
    
    echo ""
    echo "🔐 Keycloak Bootstrap for Server Info Watchdog"
    echo "=============================================="
    echo ""
    
    # Load .env defaults
    local keycloak_url="http://localhost:9090"
    local keycloak_realm="watchdog"
    local web_port="8080"
    local api_port="5000"
    
    if [ -f "$project_root/.env" ]; then
        keycloak_url=$(grep "^KEYCLOAK_URL=" "$project_root/.env" 2>/dev/null | head -n1 | cut -d'=' -f2- | tr -d ' "') || keycloak_url="http://localhost:9090"
        keycloak_realm=$(grep "^KEYCLOAK_REALM=" "$project_root/.env" 2>/dev/null | head -n1 | cut -d'=' -f2- | tr -d ' "') || keycloak_realm="watchdog"
        web_port=$(grep "^WEB_PORT=" "$project_root/.env" 2>/dev/null | head -n1 | cut -d'=' -f2- | tr -d ' "') || web_port="8080"
        api_port=$(grep "^ADMIN_API_PORT=" "$project_root/.env" 2>/dev/null | head -n1 | cut -d'=' -f2- | tr -d ' "') || api_port="5000"
    fi
    
    # Check if Keycloak is reachable
    echo "🔍 Checking Keycloak at $keycloak_url..."
    if ! curl -s --connect-timeout 5 "$keycloak_url/" >/dev/null 2>&1; then
        echo ""
        echo "❌ Cannot reach Keycloak at $keycloak_url"
        echo ""
        echo "Please ensure Keycloak is running. Start it from the dedicated repo:"
        echo "  https://github.com/Sokrates1989/keycloak.git"
        echo ""
        return 1
    fi
    echo "✅ Keycloak is reachable"
    echo ""
    
    # Collect configuration
    read_prompt "Keycloak base URL [$keycloak_url]: " input_url
    keycloak_url="${input_url:-$keycloak_url}"
    
    read_prompt "Keycloak admin username [admin]: " admin_user
    admin_user="${admin_user:-admin}"
    
    read_prompt "Keycloak admin password [admin]: " admin_password
    admin_password="${admin_password:-admin}"
    
    read_prompt "Realm name [$keycloak_realm]: " realm
    realm="${realm:-$keycloak_realm}"
    
    read_prompt "Frontend client ID [watchdog-frontend]: " frontend_client
    frontend_client="${frontend_client:-watchdog-frontend}"
    
    read_prompt "Backend client ID [watchdog-backend]: " backend_client
    backend_client="${backend_client:-watchdog-backend}"
    
    read_prompt "Frontend root URL [http://localhost:$web_port]: " frontend_url
    frontend_url="${frontend_url:-http://localhost:$web_port}"
    
    read_prompt "API root URL [http://localhost:$api_port]: " api_url
    api_url="${api_url:-http://localhost:$api_port}"
    
    echo ""
    echo "✅ Creating roles:"
    echo "   - watchdog:admin (full access)"
    echo "   - watchdog:read  (view-only access)"
    echo ""
    
    read_prompt "Create default admin user? (Y/n): " create_admin
    local admin_username=""
    local admin_email=""
    local admin_userpass=""
    
    if [[ ! "$create_admin" =~ ^[Nn]$ ]]; then
        read_prompt "Admin username [admin]: " admin_username
        admin_username="${admin_username:-admin}"
        
        read_prompt "Admin email [admin@example.com]: " admin_email
        admin_email="${admin_email:-admin@example.com}"
        
        read_prompt "Admin password [admin]: " admin_userpass
        admin_userpass="${admin_userpass:-admin}"
    fi
    
    echo ""
    echo "🚀 Bootstrapping Keycloak realm..."
    echo ""
    
    # Build user spec
    local user_spec=""
    if [ -n "$admin_username" ]; then
        user_spec="--user ${admin_username}:${admin_userpass}:watchdog:admin"
    fi
    
    # Try Python script first, fallback to Docker
    if [ -f "$project_root/scripts/keycloak_bootstrap.py" ]; then
        # Check if Python is available
        if command -v python3 >/dev/null 2>&1; then
            # Test Python command works
            if ! python3 --version >/dev/null 2>&1; then
                echo "❌ Python3 command is not working properly"
                echo "⚠️  Falling back to Docker..."
                use_docker=true
            else
                # Install requests if needed
                if ! python3 -c "import requests" 2>/dev/null; then
                    echo "📦 Installing requests module..."
                    if ! pip3 install requests --quiet; then
                        echo "❌ Failed to install requests module"
                        echo "⚠️  Falling back to Docker..."
                        use_docker=true
                    fi
                fi
                
                if [ "$use_docker" != "true" ]; then
                    if ! python3 "$project_root/scripts/keycloak_bootstrap.py" \
                        --base-url "$keycloak_url" \
                        --admin-user "$admin_user" \
                        --admin-password "$admin_password" \
                        --realm "$realm" \
                        --frontend-client-id "$frontend_client" \
                        --backend-client-id "$backend_client" \
                        --frontend-root-url "$frontend_url" \
                        --api-root-url "$api_url" \
                        $user_spec; then
                        echo "❌ Bootstrap script failed"
                        echo "⚠️  Falling back to Docker..."
                        use_docker=true
                    fi
                fi
            fi
        else
            echo "❌ Python3 is not available."
            echo "⚠️  Falling back to Docker..."
            use_docker=true
        fi
    else
        echo "❌ Bootstrap script not found at $project_root/scripts/keycloak_bootstrap.py"
        echo "⚠️  Falling back to Docker..."
        use_docker=true
    fi
    
    # Docker fallback if needed
    if [ "$use_docker" = "true" ]; then
        echo ""
        echo "🐳 Using Docker fallback for Keycloak bootstrap..."
        echo ""
        
        # Build bootstrap image if needed
        if [ ! -f "$project_root/scripts/Dockerfile" ]; then
            echo "📝 Creating Dockerfile for bootstrap..."
            cat > "$project_root/scripts/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY keycloak_bootstrap.py .
CMD ["python", "keycloak_bootstrap.py"]
EOF
        fi
        
        # Build image
        echo "🔨 Building bootstrap image..."
        if ! docker build -t server-info-watchdog-bootstrap "$project_root/scripts" >/dev/null 2>&1; then
            echo "❌ Failed to build bootstrap Docker image"
            return 1
        fi
        
        # Run bootstrap with Docker
        echo "� Running bootstrap in Docker container..."
        docker_args=(
            "run" "--rm" "-it" "--network" "host"
            "-e" "KEYCLOAK_URL=$keycloak_url"
            "-e" "KEYCLOAK_ADMIN_USER=$admin_user"
            "-e" "KEYCLOAK_ADMIN_PASSWORD=$admin_password"
            "-e" "REALM=$realm"
            "-e" "FRONTEND_CLIENT_ID=$frontend_client"
            "-e" "BACKEND_CLIENT_ID=$backend_client"
            "-e" "FRONTEND_ROOT_URL=$frontend_url"
            "-e" "API_ROOT_URL=$api_url"
        )
        
        if [ -n "$admin_username" ]; then
            docker_args+=("-e" "USER_SPEC=${admin_username}:${admin_userpass}:watchdog:admin")
        fi
        
        docker_args+=("server-info-watchdog-bootstrap")
        
        if ! docker "${docker_args[@]}"; then
            echo "❌ Docker bootstrap failed"
            return 1
        fi
    fi
    
    echo ""
    echo "✅ Keycloak bootstrap completed successfully!"
    echo ""
    echo "📝 Next steps:"
    echo "   1. Copy the backend_client_secret from above"
    echo "   2. Update your .env file with:"
    echo "      KEYCLOAK_ENABLED=true"
    echo "      KEYCLOAK_URL=$keycloak_url"
    echo "      KEYCLOAK_REALM=$realm"
    echo "      KEYCLOAK_CLIENT_ID=$backend_client"
    echo "      KEYCLOAK_CLIENT_ID_WEB=$frontend_client"
    echo "      KEYCLOAK_CLIENT_SECRET=<paste_secret_here>"
    echo ""
    
    read_prompt "Update .env with Keycloak settings now? (Y/n): " update_env
    if [[ ! "$update_env" =~ ^[Nn]$ ]]; then
        update_env_keycloak_settings "$project_root/.env" "$keycloak_url" "$realm" "$backend_client" "$frontend_client"
    fi
    
    return 0
}

# Update .env file with Keycloak settings
update_env_keycloak_settings() {
    local env_file="$1"
    local keycloak_url="$2"
    local realm="$3"
    local backend_client="$4"
    local frontend_client="$5"
    
    if [ ! -f "$env_file" ]; then
        echo "❌ .env file not found at $env_file"
        return 1
    fi
    
    # Update or add each setting
    local settings=(
        "KEYCLOAK_ENABLED=true"
        "KEYCLOAK_URL=$keycloak_url"
        "KEYCLOAK_INTERNAL_URL=http://host.docker.internal:$(echo "$keycloak_url" | sed 's|.*://||' | cut -d: -f2)"
        "KEYCLOAK_REALM=$realm"
        "KEYCLOAK_CLIENT_ID=$backend_client"
        "KEYCLOAK_CLIENT_ID_WEB=$frontend_client"
    )
    
    for setting in "${settings[@]}"; do
        local key="${setting%%=*}"
        local value="${setting#*=}"
        
        if grep -q "^${key}=" "$env_file"; then
            # Update existing
            sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
        else
            # Append new
            echo "${key}=${value}" >> "$env_file"
        fi
    done
    
    echo "✅ Updated .env with Keycloak settings"
    echo ""
    echo "⚠️  Don't forget to set KEYCLOAK_CLIENT_SECRET in .env!"
    
    read -s -p "Enter client secret to save (or press Enter to skip): " client_secret
    echo ""  # Add newline after silent input
    if [ -n "$client_secret" ]; then
        if grep -q "^KEYCLOAK_CLIENT_SECRET=" "$env_file"; then
            sed -i "s|^KEYCLOAK_CLIENT_SECRET=.*|KEYCLOAK_CLIENT_SECRET=${client_secret}|" "$env_file"
        else
            echo "KEYCLOAK_CLIENT_SECRET=${client_secret}" >> "$env_file"
        fi
        echo "✅ Client secret saved to .env"
    fi
}
