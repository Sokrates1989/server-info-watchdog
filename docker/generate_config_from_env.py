#!/usr/bin/env python3

"""Generate config/config.txt from environment variables for Server Info Watchdog.

This script runs inside the Docker container and creates:
- /code/config/config.txt for the main application

It uses the committed JSON template as a structural base and overlays values
from environment variables. Secrets (bot token) remain environment/secret-only
and are *not* written into the config file.
"""

import json
import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]


def _load_json_template(path: pathlib.Path, fallback: dict) -> dict:
    if path.exists():
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:  # pragma: no cover - defensive logging
            print(f"[WARN] Could not parse JSON template {path}: {exc}", file=sys.stderr)
    return fallback.copy()


def generate_main_config() -> None:
    """Generate /code/config/config.txt from config.txt.template + environment.

    This always overwrites config/config.txt on container start so that
    changes in the environment are reflected immediately.
    """

    template_path = ROOT / "config" / "config.txt.template"
    cfg = _load_json_template(
        template_path,
        {
            "serverName": "",
            "messageFrequency": {},
            "gluster_not_installed_handling": "warning",
            "telegram": {},
            "thresholds": {},
        },
    )

    # --- Top-level settings ---
    server_name = os.environ.get("serverName") or os.environ.get("SERVER_NAME")
    if server_name:
        cfg["serverName"] = str(server_name)

    gluster = os.environ.get("gluster_not_installed_handling") or os.environ.get(
        "GLUSTER_NOT_INSTALLED_HANDLING"
    )
    if gluster:
        cfg["gluster_not_installed_handling"] = str(gluster)

    # --- Message frequency overrides (optional) ---
    mf = cfg.setdefault("messageFrequency", {})
    for level in ("info", "warning", "error"):
        env_val = os.environ.get(f"MESSAGE_FREQUENCY_{level.upper()}")
        if env_val:
            mf[level] = str(env_val)

    # --- Telegram chat IDs from env (IDs themselves are not secrets) ---
    tg = cfg.setdefault("telegram", {})
    mapping = [
        ("errorChatIDs", "errorChatIDs", "ERROR_CHAT_IDS"),
        ("warningChatIDs", "warningChatIDs", "WARNING_CHAT_IDS"),
        ("infoChatIDs", "infoChatIDs", "INFO_CHAT_IDS"),
    ]
    for field, env_lower, env_upper in mapping:
        val = os.environ.get(env_lower) or os.environ.get(env_upper)
        if val:
            tg[field] = str(val)

    out_path = ROOT / "config" / "config.txt"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(cfg, indent=4), encoding="utf-8")
    print(f"[INFO] Generated Server Info Watchdog config at {out_path}")


def main() -> None:
    generate_main_config()


if __name__ == "__main__":
    main()
