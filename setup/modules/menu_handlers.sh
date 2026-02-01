#!/bin/bash
#
# menu_handlers.sh
#
# Module for handling menu actions in quick-start script

read_prompt() {
    local prompt="$1"
    local var_name="$2"

    if [[ -r /dev/tty ]]; then
        read -r -p "$prompt" "$var_name" < /dev/tty
    else
        read -r -p "$prompt" "$var_name"
    fi
}

handle_run_once() {
    local compose_file="$1"
    
    echo "🔍 Running watchdog check once..."
    echo ""
    COMPOSE_FILE= docker compose --env-file .env -f "$compose_file" run --rm --build watchdog python src/check_server.py
    echo ""
    echo "✅ Check completed"
}

handle_docker_compose_down() {
    local compose_file="$1"
    
    echo "🛑 Stopping containers..."
    echo "   Using compose file: $compose_file"
    echo ""
    COMPOSE_FILE= docker compose --env-file .env -f "$compose_file" down --remove-orphans
    echo ""
    echo "✅ Containers stopped"
}

handle_build_image() {
    echo "🏗️  Building production Docker image..."
    echo ""
    if [ -f "build-image/build-image.sh" ]; then
        bash build-image/build-image.sh
    else
        echo "❌ build-image/build-image.sh not found"
    fi
}

handle_build_web_image() {
    echo "🏗️  Building web UI Docker image..."
    echo ""
    if [ -f "build-image/build-web-image.sh" ]; then
        bash build-image/build-web-image.sh
    else
        echo "❌ build-image/build-web-image.sh not found"
    fi
}

handle_build_and_push_all_images() {
    # Builds and pushes all required production images.
    #
    # Images:
    # - ${IMAGE_NAME}:${IMAGE_VERSION} (python image used by watchdog + admin-api)
    # - ${WEB_IMAGE_NAME}:${WEB_IMAGE_VERSION} (nginx web UI)
    echo "🏗️  Build & Push ALL images (auto-push enabled)"
    echo ""
    
    # Read current values from .env files
    local main_image_name="sokrates1989/server-info-watchdog"
    local main_image_version="latest"
    local web_image_name="sokrates1989/server-info-watchdog-web"
    local web_image_version="latest"
    
    # Load main image defaults from .env if it exists
    if [ -f .env ]; then
        main_image_name=$(grep "^IMAGE_NAME=" .env 2>/dev/null | cut -d'=' -f2 | tr -d ' "' || echo "$main_image_name")
        main_image_version=$(grep "^IMAGE_VERSION=" .env 2>/dev/null | cut -d'=' -f2 | tr -d ' "' || echo "$main_image_version")
    fi
    
    # Load web image defaults from .ci.env if it exists
    local ci_env_file=".ci.env"
    if [ -f "$ci_env_file" ]; then
        web_image_version=$(grep "^IMAGE_VERSION=" "$ci_env_file" 2>/dev/null | cut -d'=' -f2 | tr -d ' "' || echo "$web_image_version")
    fi
    
    echo "📋 Configure all images to build and push:"
    echo ""
    
    # Collect main image information
    read -p "Main image name [$main_image_name]: " input_main_name
    main_image_name="${input_main_name:-$main_image_name}"
    
    if [ -z "$main_image_name" ]; then
        echo "❌ Main image name is required"
        return 1
    fi
    
    read -p "Main image version [$main_image_version]: " input_main_version
    main_image_version="${input_main_version:-$main_image_version}"
    
    if [ -z "$main_image_version" ]; then
        main_image_version="latest"
    fi
    
    echo ""
    
    # Collect web image information
    read -p "Web image name [$web_image_name]: " input_web_name
    web_image_name="${input_web_name:-$web_image_name}"
    
    if [ -z "$web_image_name" ]; then
        echo "❌ Web image name is required"
        return 1
    fi
    
    read -p "Web image version [$web_image_version]: " input_web_version
    web_image_version="${input_web_version:-$web_image_version}"
    
    if [ -z "$web_image_version" ]; then
        web_image_version="latest"
    fi
    
    echo ""
    echo "📦 Will build and push:"
    echo "   - ${main_image_name}:${main_image_version}"
    echo "   - ${main_image_name}:latest"
    echo "   - ${web_image_name}:${web_image_version}"
    echo "   - ${web_image_name}:latest"
    echo ""
    
    read -p "Proceed with build and push? (Y/n): " confirm_proceed
    if [[ "$confirm_proceed" =~ ^[Nn]$ ]]; then
        echo "❌ Build cancelled"
        return 1
    fi
    
    echo ""
    echo "🚀 Starting build and push process..."
    echo ""
    
    # Build and push main image with environment variables
    # Note: build-image.sh now builds both main AND web images with buildx
    echo "🏗️  Building main and web images..."
    IMAGE_NAME="$main_image_name" IMAGE_VERSION="$main_image_version" bash build-image/build-image.sh
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "❌ Image build failed"
        return $exit_code
    fi

    echo ""
    echo "✅ All images built and pushed successfully"
}

handle_start_web_ui() {
    local compose_file="$1"
    
    # Check if admin token is set
    # Load .env values if they exist for this check
    if [ -f ".env" ]; then
        # Use grep/sed to avoid shell variable export issues
        local token=$(grep "^WATCHDOG_ADMIN_TOKEN=" .env | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        if [ -z "$token" ]; then
            echo "⚠️  WARNING: WATCHDOG_ADMIN_TOKEN is not set in .env"
            echo "   The Web UI will start, but login will fail with 'Admin token not configured'."
            echo "   Please set a secure token in .env and restart."
            echo ""
            read_prompt "Continue anyway? (y/N): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo "Aborting."
                return
            fi
        fi
    fi

    echo "🌐 Starting Web UI..."
    echo "   This will start the admin API and web interface."
    echo ""

    # Force a clean slate
    echo "🧹 Cleaning up old containers..."
    COMPOSE_FILE= docker compose --env-file .env -f "$compose_file" --profile web down > /dev/null 2>&1

    if command -v show_relevant_pages_delayed >/dev/null 2>&1; then
        show_relevant_pages_delayed "$compose_file" 120
    fi

    local detach_flag=""
    if [ "${WATCHDOG_WEB_DETACHED:-false}" = "true" ]; then
        detach_flag="-d"
    fi

    echo "🏗️  Building containers (no-cache)..."
    COMPOSE_FILE= docker compose --env-file .env -f "$compose_file" --profile web build --no-cache admin-api web
    
    echo "🚀 Launching services..."
    COMPOSE_FILE= docker compose --env-file .env -f "$compose_file" --profile web up $detach_flag --force-recreate admin-api web
    echo ""
    echo "✅ Web UI started at http://localhost:${WEB_PORT:-8080}"
    echo "   Use WATCHDOG_ADMIN_TOKEN from .env to login."
}

handle_stop_web_ui() {
    local compose_file="$1"
    
    echo "🛑 Stopping Web UI..."
    COMPOSE_FILE= docker compose --env-file .env -f "$compose_file" --profile web down
    echo ""
    echo "✅ Web UI stopped"
}

handle_view_logs() {
    local compose_file="$1"
    
    echo "📋 Viewing logs..."
    COMPOSE_FILE= docker compose --env-file .env -f "$compose_file" logs -f
}

show_main_menu() {
    local compose_file="$1"
    
    local summary_msg=""
    local exit_code=0
    local choice

    while true; do
        local MENU_NEXT=1
        local MENU_RUN_ONCE=$MENU_NEXT; MENU_NEXT=$((MENU_NEXT+1))

        local MENU_MONITOR_LOGS=$MENU_NEXT; MENU_NEXT=$((MENU_NEXT+1))

        local MENU_MAINT_DOWN=$MENU_NEXT; MENU_NEXT=$((MENU_NEXT+1))

        local MENU_BUILD_ALL=$MENU_NEXT; MENU_NEXT=$((MENU_NEXT+1))

        local MENU_START_WEB=$MENU_NEXT; MENU_NEXT=$((MENU_NEXT+1))
        local MENU_STOP_WEB=$MENU_NEXT; MENU_NEXT=$((MENU_NEXT+1))

        local MENU_KEYCLOAK=$MENU_NEXT; MENU_NEXT=$((MENU_NEXT+1))

        local MENU_EXIT=$MENU_NEXT

        echo ""
        echo "================ Main Menu ================"
        echo ""
        echo "Watchdog:"
        echo "  ${MENU_RUN_ONCE}) Run check once"
        echo "  ${MENU_MONITOR_LOGS}) View logs"
        echo "  ${MENU_MAINT_DOWN}) Docker Compose Down (stop all containers)"
        echo "  ${MENU_BUILD_ALL}) Build & Push ALL Docker Images"
        echo ""
        echo "Web UI:"
        echo "  ${MENU_START_WEB}) Start Web UI (admin interface)"
        echo "  ${MENU_STOP_WEB}) Stop Web UI"
        echo ""
        echo "Authentication:"
        echo "  ${MENU_KEYCLOAK}) 🔐 Keycloak Bootstrap"
        echo ""
        echo "  ${MENU_EXIT}) Exit"
        echo ""

        if [ -n "${QUICK_START_CHOICE:-}" ]; then
            choice="${QUICK_START_CHOICE}"
            echo "Your choice (1-${MENU_EXIT}): ${choice}"
            unset QUICK_START_CHOICE
        else
            read_prompt "Your choice (1-${MENU_EXIT}): " choice
        fi

        case $choice in
          ${MENU_RUN_ONCE})
            handle_run_once "$compose_file"
            summary_msg="Check executed"
            break
            ;;
          ${MENU_MONITOR_LOGS})
            handle_view_logs "$compose_file"
            summary_msg="Logs viewed"
            break
            ;;
          ${MENU_MAINT_DOWN})
            handle_docker_compose_down "$compose_file"
            summary_msg="Docker Compose Down executed"
            break
            ;;
          ${MENU_BUILD_ALL})
            handle_build_and_push_all_images
            summary_msg="All images built & pushed"
            break
            ;;
          ${MENU_START_WEB})
            handle_start_web_ui "$compose_file"
            summary_msg="Web UI started"
            break
            ;;
          ${MENU_STOP_WEB})
            handle_stop_web_ui "$compose_file"
            summary_msg="Web UI stopped"
            break
            ;;
          ${MENU_KEYCLOAK})
            MENU_KEYCLOAK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            if [ -f "${MENU_KEYCLOAK_DIR}/menu_keycloak.sh" ]; then
                source "${MENU_KEYCLOAK_DIR}/menu_keycloak.sh"
                handle_keycloak_bootstrap
                summary_msg="Keycloak bootstrap completed"
            else
                echo "❌ Keycloak module not found"
            fi
            break
            ;;
          ${MENU_EXIT})
            echo "👋 Goodbye!"
            exit 0
            ;;
          *)
            echo "❌ Invalid selection. Please try again."
            echo ""
            continue
            ;;
        esac
    done

    echo ""
    if [ -n "$summary_msg" ]; then
        echo "✅ $summary_msg"
    fi
    echo "ℹ️  Quick-start finished. Run again for more actions."
    echo ""
    exit $exit_code
}
