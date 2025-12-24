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

handle_watchdog_start() {
    local compose_file="$1"
    
    echo "🔍 Starting Server Info Watchdog..."
    echo ""
    docker compose --env-file .env -f "$compose_file" up --build
}

handle_watchdog_start_detached() {
    local compose_file="$1"
    
    echo "🔍 Starting Server Info Watchdog (detached)..."
    echo ""
    docker compose --env-file .env -f "$compose_file" up --build -d
    echo ""
    echo "✅ Service started in background"
    echo "📋 View logs with: docker compose --env-file .env -f $compose_file logs -f"
}

handle_run_once() {
    local compose_file="$1"
    
    echo "🔍 Running watchdog check once..."
    echo ""
    docker compose --env-file .env -f "$compose_file" run --rm watchdog python src/check_server.py
    echo ""
    echo "✅ Check completed"
}

handle_docker_compose_down() {
    local compose_file="$1"
    
    echo "🛑 Stopping containers..."
    echo "   Using compose file: $compose_file"
    echo ""
    docker compose --env-file .env -f "$compose_file" down --remove-orphans
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

handle_view_logs() {
    local compose_file="$1"
    
    echo "📋 Viewing logs..."
    docker compose --env-file .env -f "$compose_file" logs -f
}

show_main_menu() {
    local compose_file="$1"
    
    local summary_msg=""
    local exit_code=0
    local choice

    while true; do
        local MENU_NEXT=1
        local MENU_RUN_START=$MENU_NEXT; MENU_NEXT=$((MENU_NEXT+1))
        local MENU_RUN_START_DETACHED=$MENU_NEXT; MENU_NEXT=$((MENU_NEXT+1))
        local MENU_RUN_ONCE=$MENU_NEXT; MENU_NEXT=$((MENU_NEXT+1))

        local MENU_MONITOR_LOGS=$MENU_NEXT; MENU_NEXT=$((MENU_NEXT+1))

        local MENU_MAINT_DOWN=$MENU_NEXT; MENU_NEXT=$((MENU_NEXT+1))

        local MENU_BUILD_IMAGE=$MENU_NEXT; MENU_NEXT=$((MENU_NEXT+1))

        local MENU_EXIT=$MENU_NEXT

        echo ""
        echo "================ Main Menu ================"
        echo ""
        echo "Run:"
        echo "  ${MENU_RUN_START}) Start Watchdog (docker compose up)"
        echo "  ${MENU_RUN_START_DETACHED}) Start Watchdog detached (background)"
        echo "  ${MENU_RUN_ONCE}) Run check once"
        echo ""
        echo "Monitoring:"
        echo "  ${MENU_MONITOR_LOGS}) View logs"
        echo ""
        echo "Maintenance:"
        echo "  ${MENU_MAINT_DOWN}) Docker Compose Down (stop containers)"
        echo ""
        echo "Build:"
        echo "  ${MENU_BUILD_IMAGE}) Build Production Docker Image"
        echo ""
        echo "  ${MENU_EXIT}) Exit"
        echo ""

        read_prompt "Your choice (1-${MENU_EXIT}): " choice

        case $choice in
          ${MENU_RUN_START})
            handle_watchdog_start "$compose_file"
            summary_msg="Watchdog started"
            break
            ;;
          ${MENU_RUN_START_DETACHED})
            handle_watchdog_start_detached "$compose_file"
            summary_msg="Watchdog started in background"
            break
            ;;
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
          ${MENU_BUILD_IMAGE})
            handle_build_image
            summary_msg="Image build executed"
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
