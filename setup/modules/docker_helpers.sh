#!/bin/bash
#
# docker_helpers.sh
#
# Module for Docker-related helper functions

check_docker_installation() {
    echo "🔍 Checking Docker installation..."
    
    if ! command -v docker &> /dev/null; then
        echo "❌ Docker is not installed!"
        echo "📥 Please install Docker from: https://www.docker.com/get-started"
        return 1
    fi

    if ! docker info &> /dev/null; then
        echo "❌ Docker daemon is not running!"
        echo "🔄 Please start Docker Desktop or the Docker service"
        return 1
    fi

    if ! docker compose version &> /dev/null; then
        echo "❌ Docker Compose is not available!"
        echo "📥 Please install a current Docker version with Compose plugin"
        return 1
    fi

    echo "✅ Docker is installed and running"
    return 0
}

read_env_variable() {
    local var_name="$1"
    local env_file="${2:-.env}"
    local default_value="${3:-}"
    
    local value
    value=$(grep "^${var_name}=" "$env_file" 2>/dev/null | head -n1 | cut -d'=' -f2- | tr -d ' "')
    
    if [ -z "$value" ]; then
        echo "$default_value"
    else
        echo "$value"
    fi
}
