#!/bin/bash
#
# menu_handlers.sh
#
# Module for handling menu actions in quick-start script

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
    docker compose --env-file .env -f "$compose_file" down
    echo ""
    echo "✅ Containers stopped"
}

handle_build_image() {
    echo "🏗️  Building production Docker image..."
    echo ""
    if [ -f "build-image/build-image.sh" ]; then
        ./build-image/build-image.sh
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
        echo "Choose an option:"
        echo "1) Start Watchdog (docker compose up)"
        echo "2) Start Watchdog detached (background)"
        echo "3) Run check once"
        echo "4) View logs"
        echo "5) Docker Compose Down (stop containers)"
        echo "6) Build Production Docker Image"
        echo "7) Exit"
        echo ""

        read -p "Your choice (1-7): " choice

        case $choice in
          1)
            handle_watchdog_start "$compose_file"
            summary_msg="Watchdog started"
            break
            ;;
          2)
            handle_watchdog_start_detached "$compose_file"
            summary_msg="Watchdog started in background"
            break
            ;;
          3)
            handle_run_once "$compose_file"
            summary_msg="Check executed"
            break
            ;;
          4)
            handle_view_logs "$compose_file"
            summary_msg="Logs viewed"
            break
            ;;
          5)
            handle_docker_compose_down "$compose_file"
            summary_msg="Docker Compose Down executed"
            break
            ;;
          6)
            handle_build_image
            summary_msg="Image build executed"
            break
            ;;
          7)
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
