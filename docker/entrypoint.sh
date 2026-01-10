#!/bin/sh
set -e

# Hand off to the actual container command (defined in docker-compose)
exec $@
