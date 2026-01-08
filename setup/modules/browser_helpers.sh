#!/bin/bash

wait_for_url() {
    local url="$1"
    local timeout="${2:-120}"
    local start_time
    start_time=$(date +%s)

    while true; do
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [ "$elapsed" -ge "$timeout" ]; then
            return 1
        fi

        local status
        status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 3 "$url" 2>/dev/null)

        if [[ "$status" =~ ^[23][0-9][0-9]$ ]]; then
            return 0
        fi

        sleep 0.5
    done
}

stop_incognito_profile_procs() {
    local profile_dir="$1"
    shift || true
    [ -z "$profile_dir" ] && return 0
    [ $# -eq 0 ] && return 0
    for pname in "$@"; do
        pkill -f "$pname.*--user-data-dir=$profile_dir" >/dev/null 2>&1 || true
    done
}

open_url() {
    local url="$1"
    local profile_base="${TMPDIR:-/tmp}"
    local edge_profile="${profile_base}/edge_incog_profile_watchdog"
    local chrome_profile="${profile_base}/chrome_incog_profile_watchdog"
    mkdir -p "$edge_profile" "$chrome_profile"

    if command -v open >/dev/null 2>&1; then
        if [ -d "/Applications/Google Chrome.app" ]; then
            stop_incognito_profile_procs "$chrome_profile" "Google Chrome"
            open -na "Google Chrome" --args --incognito --user-data-dir="$chrome_profile" "$url" >/dev/null 2>&1 || true
            return 0
        fi

        if [ -d "/Applications/Brave Browser.app" ]; then
            open -na "Brave Browser" --args --incognito "$url" >/dev/null 2>&1 || true
            return 0
        fi

        if [ -d "/Applications/Microsoft Edge.app" ]; then
            stop_incognito_profile_procs "$edge_profile" "Microsoft Edge"
            open -na "Microsoft Edge" --args -inprivate --user-data-dir="$edge_profile" "$url" >/dev/null 2>&1 || true
            return 0
        fi

        if [ -d "/Applications/Firefox.app" ]; then
            open -na "Firefox" --args -private-window "$url" >/dev/null 2>&1 || true
            return 0
        fi

        open "$url" >/dev/null 2>&1 || true
        return 0
    fi

    if command -v google-chrome >/dev/null 2>&1; then
        stop_incognito_profile_procs "$chrome_profile" "chrome" "google-chrome"
        google-chrome --incognito --user-data-dir="$chrome_profile" "$url" >/dev/null 2>&1 &
        return 0
    fi
    if command -v chromium >/dev/null 2>&1; then
        stop_incognito_profile_procs "$chrome_profile" "chromium"
        chromium --incognito --user-data-dir="$chrome_profile" "$url" >/dev/null 2>&1 &
        return 0
    fi
    if command -v chromium-browser >/dev/null 2>&1; then
        stop_incognito_profile_procs "$chrome_profile" "chromium-browser"
        chromium-browser --incognito --user-data-dir="$chrome_profile" "$url" >/dev/null 2>&1 &
        return 0
    fi
    if command -v microsoft-edge >/dev/null 2>&1; then
        stop_incognito_profile_procs "$edge_profile" "microsoft-edge"
        microsoft-edge -inprivate --user-data-dir="$edge_profile" "$url" >/dev/null 2>&1 &
        return 0
    fi
    if command -v firefox >/dev/null 2>&1; then
        firefox -private-window "$url" >/dev/null 2>&1 &
        return 0
    fi

    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url" >/dev/null 2>&1 || true
        return 0
    fi

    echo "[WARN] No browser opener found. Please open manually: $url"
}

show_relevant_pages_delayed() {
    local compose_file="$1"
    local timeout="${2:-120}"

    local web_port="8080"
    if command -v read_env_variable >/dev/null 2>&1; then
        web_port="$(read_env_variable WEB_PORT .env 8080)"
    fi

    local web_url="http://localhost:${web_port}"
    local web_health_url="http://localhost:${web_port}/health"

    echo ""
    echo "========================================"
    echo "  Services will be accessible at:"
    echo "  - Web: ${web_url}"
    echo "========================================"
    echo ""
    echo "🌐 Browser will open automatically when services are ready..."
    echo ""

    (
        if wait_for_url "$web_health_url" "$timeout"; then
            echo "✅ Web UI is ready!"
        else
            echo "⚠️  Timeout waiting for Web UI"
        fi

        sleep 1
        open_url "$web_url"
    ) &
}
