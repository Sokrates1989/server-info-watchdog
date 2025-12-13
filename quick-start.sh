#!/bin/bash
#
# quick-start.sh
#
# Quick start tool for Server Info Watchdog:
# 1. Checks Docker installation
# 2. Creates .env from template if needed
# 3. Provides menu for common operations

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="${SCRIPT_DIR}/setup"

# Source modules
source "${SETUP_DIR}/modules/docker_helpers.sh"
source "${SETUP_DIR}/modules/menu_handlers.sh"

echo "🔍 Server Info Watchdog - Quick Start"
echo "======================================"
echo ""

# Docker availability check
if ! check_docker_installation; then
    exit 1
fi
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo "⚠️  .env file not found"
    echo ""
    if [ -f setup/.env.template ]; then
        read -p "Create .env from template? (Y/n): " create_env
        if [[ ! "$create_env" =~ ^[Nn]$ ]]; then
            cp setup/.env.template .env
            echo "✅ .env created from template"
            echo "⚠️  Please edit .env with your configuration before continuing"
            echo ""

            EDITOR_CMD="${EDITOR:-nano}"
            if ! command -v "$EDITOR_CMD" >/dev/null 2>&1; then
                EDITOR_CMD="vi"
            fi
            read -p "Open .env now in $EDITOR_CMD? (Y/n): " open_env
            if [[ ! "$open_env" =~ ^[Nn]$ ]]; then
                "$EDITOR_CMD" .env
            fi

            read -p "Press Enter to continue after editing .env..."
        else
            echo "❌ Cannot continue without .env file"
            exit 1
        fi
    else
        echo "❌ setup/.env.template not found!"
        exit 1
    fi
    echo ""
fi

# Determine compose file
COMPOSE_FILE="local-deployment/docker-compose.yml"

if [ ! -f "$COMPOSE_FILE" ]; then
    echo "⚠️  $COMPOSE_FILE not found"
    # Fall back to old location
    if [ -f "docker-compose.yml" ]; then
        COMPOSE_FILE="docker-compose.yml"
        echo "   Using fallback: $COMPOSE_FILE"
    fi
fi

echo "📋 Using compose file: $COMPOSE_FILE"
echo ""

# Show main menu
show_main_menu "$COMPOSE_FILE"
