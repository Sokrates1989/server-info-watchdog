#!/bin/sh
set -e

# Generate config from environment variables before starting the app
if [ -x "/code/docker/generate_config_from_env.py" ]; then
    python /code/docker/generate_config_from_env.py
fi

# Hand off to the actual container command (defined in docker-compose)
exec "$@"
