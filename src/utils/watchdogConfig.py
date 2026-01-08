"""
Module: watchdogConfig.py
Author: Server Info Watchdog
Date: 2024
Version: 1.0.0

Description:
    Centralized configuration loader for the watchdog service.
    Reads all settings from environment variables or a mounted watchdog.env file.
    Supports JSON-formatted thresholds and message frequency settings.

Usage:
    from watchdogConfig import WatchdogConfig
    config = WatchdogConfig()
    thresholds = config.get_thresholds('cpu')
"""

import os
import json
from typing import Optional, Any
from dotenv import dotenv_values


class Thresholds:
    """Container for warning and error threshold values."""

    def __init__(self, warning: str, error: str):
        """Initialize threshold values.

        Args:
            warning (str): Warning threshold value.
            error (str): Error threshold value.
        """
        self.warning = warning
        self.error = error


class WatchdogConfig:
    """Centralized configuration manager for the watchdog service.

    Loads configuration from environment variables and/or a mounted
    watchdog.env file. Environment variables take precedence over
    values in the env file.

    Attributes:
        server_name (str): Name of the server being monitored.
        gluster_not_installed_handling (str): How to handle missing Gluster.
        message_frequency (dict): Info/warning/error message frequency.
        thresholds (dict): All threshold configurations.
        error_chat_ids (list): Telegram chat IDs for errors.
        warning_chat_ids (list): Telegram chat IDs for warnings.
        info_chat_ids (list): Telegram chat IDs for info messages.
        admin_token (str): Admin authentication token for the web UI.
    """

    # Default path to the mounted env file inside container
    DEFAULT_ENV_FILE = "/code/watchdog.env"

    # Default thresholds (used if not specified in env)
    DEFAULT_THRESHOLDS = {
        "timestampAgeMinutes": {"warning": "65", "error": "185"},
        "cpu": {"warning": "80", "error": "100"},
        "disk": {"warning": "75", "error": "90"},
        "memory": {"warning": "75", "error": "90"},
        "network_up": {"warning": "0", "error": "0"},
        "network_down": {"warning": "0", "error": "0"},
        "network_total": {"warning": "50000000", "error": "100000000"},
        "processes": {"warning": "150", "error": "270"},
        "users": {"warning": "2", "error": "3"},
        "updates": {"warning": "10", "error": "25"},
        "system_restart": {"warning": "10d", "error": "50d"},
        "linux_server_state_tool": {"warning": "1", "error": "5"},
        "gluster_unhealthy_peers": {"warning": "1", "error": "2"},
        "gluster_unhealthy_volumes": {"warning": "1", "error": "2"},
    }

    # Default message frequency
    DEFAULT_MESSAGE_FREQUENCY = {
        "info": "1h",
        "warning": "1d",
        "error": "3d",
    }

    def __init__(self, env_file_path: Optional[str] = None):
        """Initialize the configuration from environment and/or env file.

        Args:
            env_file_path (str, optional): Path to the watchdog.env file.
                Defaults to /code/watchdog.env if not specified.
        """
        self._env_file_path = env_file_path or os.getenv(
            "WATCHDOG_ENV_FILE", self.DEFAULT_ENV_FILE
        )
        self._file_values = {}
        self._load_env_file()
        self._load_config()

    def _load_env_file(self) -> None:
        """Load values from the env file if it exists."""
        print(f"DEBUG: Attempting to load env file: {self._env_file_path}")
        if os.path.isfile(self._env_file_path):
            try:
                self._file_values = dotenv_values(self._env_file_path)
                print(f"DEBUG: Successfully loaded {len(self._file_values)} keys from {self._env_file_path}")
                if "WATCHDOG_ADMIN_TOKEN" in self._file_values:
                    print("DEBUG: Found WATCHDOG_ADMIN_TOKEN in file")
            except Exception as e:
                print(f"❌ Error: Could not load env file {self._env_file_path}: {e}")
                self._file_values = {}
        else:
            print(f"⚠️  Warning: Config file not found at {self._env_file_path}")

    def _get_value(self, key: str, default: Any = None) -> Any:
        """
        Get config value with tracing.
        Priority: 
        1. WATCHDOG_ADMIN_TOKEN: Environment > watchdog.env (Security/Lockout protection)
        2. Others: watchdog.env > Environment (UI update priority)
        """
        env_val = os.getenv(key)
        file_val = self._file_values.get(key)
        
        # Trace for critical keys
        is_critical = "TOKEN" in key.upper() or "PATH" in key.upper()
        
        # SECURITY EXCEPTION: Always prefer ENV for the Admin Token to prevent lockout
        # if the watchdog.env file gets corrupted or set to a default value.
        if key == "WATCHDOG_ADMIN_TOKEN" and env_val is not None and env_val.strip() != "":
            if is_critical:
                print(f"DEBUG: Config {key} loaded from ENV (Security Priority): [MASKED]")
            return env_val.strip().strip('"')

        # 1. Check File Value (Priority for updates via UI)
        if file_val is not None and str(file_val).strip() != "":
            val = str(file_val).strip().strip('"')
            if is_critical:
                print(f"DEBUG: Config {key} loaded from FILE: [MASKED]")
            return val

        # 2. Check Environment Variable
        if env_val is not None and env_val.strip() != "":
            if is_critical:
                masked = "[MASKED]" if "TOKEN" in key.upper() else env_val
                print(f"DEBUG: Config {key} loaded from ENV: {masked}")
            return env_val.strip().strip('"')
            
        # 3. Fallback to Default
        if default is not None:
            # Only log if it's not the default "not found" value
            if not isinstance(default, str) or "not found" not in default.lower():
                print(f"DEBUG: {key} not found, using default: {default}")
        return default

    def _load_config(self) -> None:
        """Load all configuration values."""
        # Server identification
        self.server_name = self._get_value(
            "serverName",
            self._get_value("SERVER_NAME", "Unknown - Please set serverName"),
        )

        # Gluster handling
        self.gluster_not_installed_handling = self._get_value(
            "gluster_not_installed_handling",
            self._get_value("GLUSTER_NOT_INSTALLED_HANDLING", "error"),
        )

        # Load thresholds from JSON env var or use defaults
        self._load_thresholds()

        # Load message frequency from JSON env var or use defaults
        self._load_message_frequency()

        # Load Telegram chat IDs
        self._load_chat_ids()

        # Admin token for web UI
        self.admin_token = self._get_value(
            "WATCHDOG_ADMIN_TOKEN",
            self._get_value("watchdog_admin_token", ""),
        )
        
        # Debug logging for config loading
        if os.getenv("DEBUG_WATCHDOG_CONFIG", "false").lower() in ("true", "1", "yes"):
            print(f"DEBUG: WatchdogConfig loaded from {self._env_file_path}")
            print(f"DEBUG: server_name={self.server_name}")
            print(f"DEBUG: admin_token_set={'Yes' if self.admin_token else 'No'}")
            if self.admin_token:
                 # Print first/last char to verify without leaking
                print(f"DEBUG: admin_token starts with: {self.admin_token[0] if self.admin_token else 'N/A'}")

    def _load_thresholds(self) -> None:
        """Load threshold configuration from JSON env var or defaults."""
        thresholds_json = self._get_value("WATCHDOG_THRESHOLDS_JSON", "")

        if thresholds_json:
            try:
                self.thresholds = json.loads(thresholds_json)
            except json.JSONDecodeError as e:
                print(f"Warning: Invalid WATCHDOG_THRESHOLDS_JSON: {e}")
                print("Using default thresholds.")
                self.thresholds = self.DEFAULT_THRESHOLDS.copy()
        else:
            self.thresholds = self.DEFAULT_THRESHOLDS.copy()

    def _load_message_frequency(self) -> None:
        """Load message frequency configuration from JSON env var or defaults."""
        freq_json = self._get_value("WATCHDOG_MESSAGE_FREQUENCY_JSON", "")

        if freq_json:
            try:
                self.message_frequency = json.loads(freq_json)
            except json.JSONDecodeError as e:
                print(f"Warning: Invalid WATCHDOG_MESSAGE_FREQUENCY_JSON: {e}")
                print("Using default message frequency.")
                self.message_frequency = self.DEFAULT_MESSAGE_FREQUENCY.copy()
        else:
            self.message_frequency = self.DEFAULT_MESSAGE_FREQUENCY.copy()

    def _load_chat_ids(self) -> None:
        """Load Telegram chat IDs from env vars."""
        # Error chat IDs
        error_ids_str = self._get_value("errorChatIDs", self._get_value("ERROR_CHAT_IDS", ""))
        self.error_chat_ids = self._parse_chat_ids(error_ids_str)

        # Warning chat IDs
        warning_ids_str = self._get_value("warningChatIDs", self._get_value("WARNING_CHAT_IDS", ""))
        self.warning_chat_ids = self._parse_chat_ids(warning_ids_str)

        # Info chat IDs
        info_ids_str = self._get_value("infoChatIDs", self._get_value("INFO_CHAT_IDS", ""))
        self.info_chat_ids = self._parse_chat_ids(info_ids_str)

    def _parse_chat_ids(self, chat_ids_string: str) -> list:
        """Parse a comma-separated string of chat IDs into a list.

        Args:
            chat_ids_string (str): Comma-separated chat IDs.

        Returns:
            list: List of sanitized chat ID strings.
        """
        if not chat_ids_string:
            return []
        ids = chat_ids_string.split(",")
        return [cid.strip().strip('"') for cid in ids if cid.strip()]

    def get_thresholds(self, key: str) -> Thresholds:
        """Get threshold values for a specific metric.

        Args:
            key (str): Threshold key (e.g., 'cpu', 'disk', 'memory').

        Returns:
            Thresholds: Object with warning and error threshold values.

        Raises:
            KeyError: If the threshold key is not found.
        """
        if key not in self.thresholds:
            raise KeyError(f"Threshold key '{key}' not found in configuration.")

        threshold_data = self.thresholds[key]
        return Thresholds(
            warning=str(threshold_data.get("warning", "0")),
            error=str(threshold_data.get("error", "0")),
        )

    def get_message_frequency(self, level: str) -> str:
        """Get message frequency for a specific level.

        Args:
            level (str): Message level ('info', 'warning', 'error').

        Returns:
            str: Frequency string (e.g., '1h', '1d', '3d').
        """
        return self.message_frequency.get(level, "1h")

    def get_env_file_path(self) -> str:
        """Get the path to the env file.

        Returns:
            str: Path to the watchdog.env file.
        """
        return self._env_file_path

    def reload(self) -> None:
        """Reload configuration from the env file and environment variables."""
        self._load_env_file()
        self._load_config()

    def to_dict(self) -> dict:
        """Export current configuration as a dictionary.

        Returns:
            dict: All configuration values.
        """
        return {
            "server_name": self.server_name,
            "gluster_not_installed_handling": self.gluster_not_installed_handling,
            "thresholds": self.thresholds,
            "message_frequency": self.message_frequency,
            "error_chat_ids": self.error_chat_ids,
            "warning_chat_ids": self.warning_chat_ids,
            "info_chat_ids": self.info_chat_ids,
            "admin_token": "***" if self.admin_token else "",
        }


# Global singleton instance for convenience
_config_instance: Optional[WatchdogConfig] = None


def get_config() -> WatchdogConfig:
    """Get the global WatchdogConfig singleton instance.

    Returns:
        WatchdogConfig: The global configuration instance.
    """
    global _config_instance
    if _config_instance is None:
        _config_instance = WatchdogConfig()
    return _config_instance


def reload_config() -> WatchdogConfig:
    """Reload the global configuration and return the updated instance.

    Returns:
        WatchdogConfig: The reloaded configuration instance.
    """
    global _config_instance
    _config_instance = WatchdogConfig()
    return _config_instance
