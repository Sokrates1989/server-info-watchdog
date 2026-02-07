"""
Module: admin_api.py
Author: Server Info Watchdog
Date: 2024
Version: 1.0.0

Description:
    Simple Flask-based admin API for the watchdog web UI.
    Provides endpoints to read/write the watchdog.env configuration file.
    Protected by WATCHDOG_ADMIN_TOKEN authentication.

Endpoints:
    GET  /v1/admin/config - Read current configuration
    POST /v1/admin/config - Update configuration
    GET  /health         - Health check endpoint
"""

import json
import os
import sys
import time
from functools import wraps
from typing import Any, Dict, List, Optional

from flask import Flask, jsonify, request

# Add utils path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "utils"))

from watchdogConfig import WatchdogConfig, reload_config, get_config as get_watchdog_config

# Keycloak authentication (optional)
try:
    from keycloak_auth import (
        get_keycloak_enabled,
        get_keycloak_auth,
        validate_bearer_token,
        KeycloakUser,
        ROLE_ADMIN,
        ROLE_READ,
    )
    KEYCLOAK_AVAILABLE = True
except ImportError:
    KEYCLOAK_AVAILABLE = False
    get_keycloak_enabled = lambda: False
    get_keycloak_auth = lambda: None
    validate_bearer_token = lambda x: None
    KeycloakUser = None
    ROLE_ADMIN = "watchdog:admin"
    ROLE_READ = "watchdog:read"

CODE_VERSION = "1.0.6 - Build Trace"
BOOT_ID = os.urandom(4).hex().upper()

app = Flask(__name__)

# Configuration
ENV_FILE_PATH = os.getenv("WATCHDOG_ENV_FILE", "/code/watchdog.env")


@app.errorhandler(Exception)
def handle_exception(e):
    """Handle all unhandled exceptions by returning a JSON response.

    Args:
        e: The exception that was raised.

    Returns:
        JSON response with error details.
    """
    # Pass through HTTP errors
    from werkzeug.exceptions import HTTPException
    if isinstance(e, HTTPException):
        return jsonify({"success": False, "error": str(e)}), e.code

    # Handle non-HTTP exceptions
    return jsonify({"success": False, "error": f"Internal Server Error: {str(e)}"}), 500


def get_admin_token() -> str:
    """Get the admin token from the centralized configuration.
    Forces a config reload to ensure we have the latest value from watchdog.env.

    Returns:
        str: The admin authentication token.
    """
    config = reload_config()
    token = config.admin_token
    
    # Debug logging for troubleshooting
    if os.getenv("DEBUG_WATCHDOG_CONFIG", "false").lower() in ("true", "1", "yes"):
        print(f"DEBUG: Auth attempt - Admin token configured: {'Yes' if token else 'No'}")
        if token:
            print(f"DEBUG: Token source: {config.get_env_file_path()}")
            
    return token


def _validate_token_auth() -> bool:
    """Validate admin token authentication.

    Returns:
        True if token auth succeeds, False otherwise.
    """
    admin_token = get_admin_token()
    if not admin_token:
        return False

    # Check header first, then query parameter
    provided_token = request.headers.get("X-Watchdog-Admin-Token", "")
    if not provided_token:
        provided_token = request.args.get("token", "")

    return provided_token == admin_token


def _validate_keycloak_auth() -> Optional[KeycloakUser]:
    """Validate Keycloak JWT authentication.

    Returns:
        KeycloakUser if valid, None otherwise.
    """
    if not KEYCLOAK_AVAILABLE or not get_keycloak_enabled():
        return None

    auth_header = request.headers.get("Authorization", "")
    return validate_bearer_token(auth_header)


def _check_user_has_role(user: Optional[KeycloakUser], required_roles: List[str]) -> bool:
    """Check if user has any of the required roles.

    Args:
        user: KeycloakUser or None (token auth).
        required_roles: List of role names that grant access.

    Returns:
        True if user has access (token auth or has required role).
    """
    # Token auth has full access
    if user is None:
        return True

    # Check if user has any of the required roles
    if KEYCLOAK_AVAILABLE and KeycloakUser is not None:
        return user.has_any_role(required_roles)

    return False


def require_auth(f):
    """Decorator to require admin authentication for endpoints.

    Supports both legacy token auth and Keycloak JWT auth.
    Token auth gets full access; Keycloak users need watchdog:read or watchdog:admin role.

    Args:
        f: The function to wrap.

    Returns:
        The wrapped function that checks authentication.
    """
    @wraps(f)
    def decorated(*args, **kwargs):
        # Try Keycloak first if enabled
        keycloak_user = _validate_keycloak_auth()
        if keycloak_user is not None:
            # User authenticated via Keycloak, check roles
            if not _check_user_has_role(keycloak_user, [ROLE_ADMIN, ROLE_READ]):
                return jsonify({
                    "error": f"Access denied. Required role: {ROLE_READ} or {ROLE_ADMIN}."
                }), 403
            # Store user in request context for later use
            request.keycloak_user = keycloak_user
            return f(*args, **kwargs)

        # Fallback to token auth
        if _validate_token_auth():
            request.keycloak_user = None
            return f(*args, **kwargs)

        # Neither auth method succeeded
        admin_token = get_admin_token()
        if not admin_token and not get_keycloak_enabled():
            return jsonify({"error": "Admin token not configured"}), 503

        return jsonify({"error": "Unauthorized"}), 401

    return decorated


def require_write_access(f):
    """Decorator to require write access (admin role only) for endpoints.

    Token auth gets full access; Keycloak users need watchdog:admin role.

    Args:
        f: The function to wrap.

    Returns:
        The wrapped function that checks authentication and admin role.
    """
    @wraps(f)
    def decorated(*args, **kwargs):
        # Try Keycloak first if enabled
        keycloak_user = _validate_keycloak_auth()
        if keycloak_user is not None:
            # User authenticated via Keycloak, check admin role
            if not _check_user_has_role(keycloak_user, [ROLE_ADMIN]):
                return jsonify({
                    "error": f"Access denied. Required role: {ROLE_ADMIN}. Write operations require admin privileges."
                }), 403
            request.keycloak_user = keycloak_user
            return f(*args, **kwargs)

        # Fallback to token auth (has full access)
        if _validate_token_auth():
            request.keycloak_user = None
            return f(*args, **kwargs)

        # Neither auth method succeeded
        admin_token = get_admin_token()
        if not admin_token and not get_keycloak_enabled():
            return jsonify({"error": "Admin token not configured"}), 503

        return jsonify({"error": "Unauthorized"}), 401

    return decorated


@app.route("/health", methods=["GET"])
def health_check():
    """Health check endpoint for container orchestration.

    Returns:
        JSON response with health status.
    """
    return jsonify({"status": "healthy", "service": "watchdog-admin-api"})


@app.route("/v1/admin/config", methods=["GET"])
@require_auth
def handle_get_config():
    """Get the current watchdog configuration.

    Returns:
        JSON response with current configuration values.
    """
    try:
        config = reload_config()
        return jsonify({
            "success": True,
            "config": {
                "serverName": config.server_name,
                "glusterNotInstalledHandling": config.gluster_not_installed_handling,
                "thresholds": config.thresholds,
                "messageFrequency": config.message_frequency,
                "errorChatIds": config.error_chat_ids,
                "warningChatIds": config.warning_chat_ids,
                "infoChatIds": config.info_chat_ids,
            },
            "envFilePath": config.get_env_file_path(),
            "envFileExists": os.path.isfile(config.get_env_file_path()),
        })
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@app.route("/v1/admin/config", methods=["POST"])
@require_write_access
def handle_update_config():
    """Update the watchdog configuration by writing to the env file.

    Expects JSON body with configuration values to update.

    Returns:
        JSON response indicating success or failure.
    """
    try:
        data = request.get_json()
        if not data:
            return jsonify({"success": False, "error": "No data provided"}), 400

        # Read existing env file content to preserve untracked keys (like WATCHDOG_ADMIN_TOKEN)
        env_content = {}
        if os.path.isfile(ENV_FILE_PATH):
            with open(ENV_FILE_PATH, "r") as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#") and "=" in line:
                        key, _, value = line.partition("=")
                        env_content[key.strip()] = value.strip()

        # Update with new values from UI
        if "serverName" in data:
            env_content["serverName"] = data["serverName"]

        if "glusterNotInstalledHandling" in data:
            env_content["gluster_not_installed_handling"] = data["glusterNotInstalledHandling"]

        if "thresholds" in data:
            env_content["WATCHDOG_THRESHOLDS_JSON"] = json.dumps(data["thresholds"])

        if "messageFrequency" in data:
            env_content["WATCHDOG_MESSAGE_FREQUENCY_JSON"] = json.dumps(data["messageFrequency"])

        if "errorChatIds" in data:
            env_content["errorChatIDs"] = ",".join(data["errorChatIds"])

        if "warningChatIds" in data:
            env_content["warningChatIDs"] = ",".join(data["warningChatIds"])

        if "infoChatIds" in data:
            env_content["infoChatIDs"] = ",".join(data["infoChatIds"])

        # Write back to env file
        with open(ENV_FILE_PATH, "w") as f:
            f.write("# Server Info Watchdog Configuration\n")
            f.write("# Updated via Admin API\n\n")
            # Sort keys to keep file organized
            for key in sorted(env_content.keys()):
                f.write(f"{key}={env_content[key]}\n")

        # Force a fresh reload of the global config instance
        reload_config()

        return jsonify({"success": True, "message": "Configuration updated"})

    except PermissionError:
        return jsonify({
            "success": False,
            "error": "Permission denied. Env file may be mounted read-only."
        }), 403
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@app.route("/v1/admin/config/defaults", methods=["GET"])
@require_auth
def handle_get_defaults():
    """Get the default configuration values.

    Returns:
        JSON response with default threshold and frequency values.
    """
    return jsonify({
        "success": True,
        "defaults": {
            "thresholds": WatchdogConfig.DEFAULT_THRESHOLDS,
            "messageFrequency": WatchdogConfig.DEFAULT_MESSAGE_FREQUENCY,
        }
    })


@app.route("/v1/admin/system-state", methods=["GET"])
@require_auth
def handle_get_system_state():
    """Get the current system state from serverInfo.
    
    Returns:
        JSON response with current system metrics and thresholds.
    """
    try:
        server_info_path = os.getenv("SERVER_INFO_PATH", "/code/serverInfo")
        system_info_file = os.path.join(server_info_path, "system_info.json")
        
        if not os.path.isfile(system_info_file):
            return jsonify({
                "success": False,
                "error": "System info file not found",
                "path": system_info_file
            }), 404
        
        # Read current system state
        with open(system_info_file, 'r') as f:
            system_state = json.load(f)
        
        # Get current thresholds from config
        config = get_watchdog_config()
        thresholds = getattr(config, 'thresholds', {})
        
        # Combine current state with thresholds for easy comparison
        response = {
            "success": True,
            "data": {
                "timestamp": system_state.get("timestamp", {}).get("human_readable_format"),
                "serverName": system_state.get("system_info", {}).get("hostname"),
                "current": {
                    "cpu": float(system_state.get("cpu", {}).get("last_15min_cpu_percentage", 0)),
                    "disk": float(system_state.get("disk", {}).get("disk_usage_percentage", "0").replace('%', '')),
                    "memory": float(system_state.get("memory", {}).get("memory_usage_percentage", 0)),
                    "processes": int(system_state.get("processes", {}).get("amount_processes", 0)),
                    "users": int(system_state.get("users", {}).get("logged_in_users", 0)),
                    "updates": int(system_state.get("updates", {}).get("amount_of_available_updates", 0)),
                    "system_restart": int(int(system_state.get("system_restart", {}).get("time_elapsed_seconds", 0) or 0) / 86400),
                    "linux_server_state_tool": int(system_state.get("linux_server_state_tool", {}).get("behind_count", 0)),
                    "gluster_unhealthy_peers": int(system_state.get("gluster", {}).get("number_of_unhealthy_peers", 0)),
                    "gluster_unhealthy_volumes": int(system_state.get("gluster", {}).get("number_of_unhealthy_volumes", 0)),
                    "kernel_versions_behind": int(system_state.get("kernel", {}).get("versions_behind", 0)),
                    "network_up": float(system_state.get("network", {}).get("upstream_avg_bits", 0)),
                    "network_down": float(system_state.get("network", {}).get("downstream_avg_bits", 0)),
                    "network_total": float(system_state.get("network", {}).get("total_network_avg_bits", 0)),
                    "timestampAgeMinutes": int((time.time() - int(system_state.get("timestamp", {}).get("unix_format", 0))) / 60)
                },
                "thresholds": thresholds
            }
        }
        
        return jsonify(response)
        
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


if __name__ == "__main__":
    port = int(os.getenv("ADMIN_API_PORT", "5000"))
    debug = os.getenv("FLASK_DEBUG", "false").lower() in ("true", "1", "yes")
    
    # Force a reload at startup to get latest values
    config = reload_config()
    
    print("=" * 60)
    print(f"🚀 SERVER INFO WATCHDOG - ADMIN API (v{CODE_VERSION})")
    print(f"   Boot ID: {BOOT_ID}")
    print(f"   Time: {os.popen('date').read().strip()}")
    print(f"   Port: {port}")
    print(f"   Working Dir: {os.getcwd()}")
    print(f"   Config File Path: {config.get_env_file_path()}")
    print(f"   File Exists: {'✅ Yes' if os.path.isfile(config.get_env_file_path()) else '❌ No'}")
    
    # Log ALL environment variables starting with WATCHDOG_
    print("   --- Environment Scan ---")
    for key, val in os.environ.items():
        if key.startswith("WATCHDOG_"):
            masked_val = "[MASKED]" if "TOKEN" in key.upper() else val
            print(f"   - {key}={masked_val}")

    if os.path.isfile(config.get_env_file_path()):
        try:
            with open(config.get_env_file_path(), 'r') as f:
                lines = f.readlines()
                token_lines = [l for l in lines if "WATCHDOG_ADMIN_TOKEN" in l]
                print(f"   --- File Scan ({config.get_env_file_path()}) ---")
                print(f"   Token lines found: {len(token_lines)}")
                for tl in token_lines:
                    prefix = tl.strip().split('=')[0]
                    is_commented = tl.strip().startswith("#")
                    print(f"   - {prefix} (Commented: {is_commented})")
        except Exception as e:
            print(f"   Error reading file: {e}")

    token_status = "[CONFIGURED]" if config.admin_token else "[MISSING - LOGIN WILL FAIL]"
    print(f"   Final Resolved Admin Token Status: {token_status}")
    
    if not config.admin_token:
        print("\n⚠️  CRITICAL: WATCHDOG_ADMIN_TOKEN is resolved as EMPTY!")
    print("=" * 60)
    
    app.run(host="0.0.0.0", port=port, debug=debug)
