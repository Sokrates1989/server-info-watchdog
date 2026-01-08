#!/bin/sh
set -e

# Configuration is now loaded directly from environment variables and
# the mounted watchdog.env file by the watchdogConfig module.
# No pre-processing required.

# Hand off to the actual container command (defined in docker-compose)
exec "$@"
