#!/bin/sh
# Generate keycloak-config.js from environment variables
# This script runs at container startup before nginx starts

CONFIG_FILE="/usr/share/nginx/html/keycloak-config.js"
CLIENT_ID="${KEYCLOAK_CLIENT_ID_WEB:-${KEYCLOAK_CLIENT_ID:-watchdog-frontend}}"

# Generate the config file
cat > "$CONFIG_FILE" << EOF
/**
 * Keycloak Configuration (auto-generated at container startup)
 */
window.KEYCLOAK_ENABLED = ${KEYCLOAK_ENABLED:-false};
window.KEYCLOAK_URL = '${KEYCLOAK_URL:-http://localhost:9090}';
window.KEYCLOAK_REALM = '${KEYCLOAK_REALM:-watchdog}';
window.KEYCLOAK_CLIENT_ID = '${CLIENT_ID}';
EOF

echo "[keycloak-config] Generated $CONFIG_FILE with KEYCLOAK_ENABLED=${KEYCLOAK_ENABLED:-false}"

# Execute the original command (nginx)
exec "$@"
