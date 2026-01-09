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
from functools import wraps
from typing import Any, Dict, Optional

from flask import Flask, jsonify, request

# Add utils path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "utils"))

from watchdogConfig import WatchdogConfig, reload_config, get_config as get_watchdog_config

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


def require_auth(f):
    """Decorator to require admin authentication for endpoints.

    Args:
        f: The function to wrap.

    Returns:
        The wrapped function that checks authentication.
    """
    @wraps(f)
    def decorated(*args, **kwargs):
        admin_token = get_admin_token()

        if not admin_token:
            return jsonify({"error": "Admin token not configured"}), 503

        # Check header first, then query parameter
        provided_token = request.headers.get("X-Watchdog-Admin-Token", "")
        if not provided_token:
            provided_token = request.args.get("token", "")

        if provided_token != admin_token:
            # Mask tokens for security but show if they are empty
            p_masked = provided_token[:1] + "..." if provided_token else "EMPTY"
            a_masked = admin_token[:1] + "..." if admin_token else "EMPTY"
            print(f"AUTH FAILED: Provided '{p_masked}' != Expected '{a_masked}'")
            return jsonify({"error": "Unauthorized"}), 401

        return f(*args, **kwargs)
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
@require_auth
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
        thresholds = {}
        if config.thresholds_json:
            try:
                thresholds = json.loads(config.thresholds_json)
            except json.JSONDecodeError:
                pass
        
        # Combine current state with thresholds for easy comparison
        response = {
            "success": True,
            "data": {
                "timestamp": system_state.get("timestamp"),
                "serverName": system_state.get("serverName"),
                "current": {
                    "cpu": system_state.get("cpu", {}).get("usage_percent", 0),
                    "disk": system_state.get("disk", {}).get("usage_percent", 0),
                    "memory": system_state.get("memory", {}).get("usage_percent", 0),
                    "processes": system_state.get("processes", {}).get("count", 0),
                    "users": system_state.get("users", {}).get("count", 0),
                    "updates": system_state.get("updates", {}).get("count", 0),
                    "system_restart": system_state.get("system", {}).get("uptime_days", 0),
                    "linux_server_state_tool": system_state.get("linux_server_state_tool", {}).get("commits_behind", 0),
                    "gluster_unhealthy_peers": system_state.get("gluster", {}).get("unhealthy_peers", 0),
                    "gluster_unhealthy_volumes": system_state.get("gluster", {}).get("unhealthy_volumes", 0),
                    "network_up": system_state.get("network", {}).get("up_bps", 0),
                    "network_down": system_state.get("network", {}).get("down_bps", 0),
                    "network_total": system_state.get("network", {}).get("total_bps", 0),
                    "timestampAgeMinutes": system_state.get("timestamp_age_minutes", 0)
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
