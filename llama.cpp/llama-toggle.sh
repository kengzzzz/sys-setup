#!/usr/bin/env bash

set -u

project_dir="/home/keng/Documents/sys-setup/llama.cpp"
compose=(docker compose --project-directory "$project_dir" -f "$project_dir/docker-compose.yml")
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}/llama.cpp"
non_mtp_env="$runtime_dir/non-mtp.env"

notify() {
    notify-send --app-name="llama.cpp" "$1" "$2"
}

is_running() {
    [[ -n "$("${compose[@]}" ps --status running -q llama-server 2>/dev/null)" ]]
}

current_mode() {
    if ! is_running; then
        printf 'stopped\n'
    elif docker inspect llama-server --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
        | grep -q '^LLAMA_ARG_SPEC_'; then
        printf 'MTP\n'
    else
        printf 'non-MTP\n'
    fi
}

start() {
    local mode="$1"
    local env_file="$project_dir/.env"

    if [[ "$mode" == "non-MTP" ]]; then
        mkdir -p "$runtime_dir"
        chmod 700 "$runtime_dir"
        umask 077
        grep -v '^LLAMA_ARG_SPEC_' "$project_dir/.env" > "$non_mtp_env"
        env_file="$non_mtp_env"
    fi

    if is_running && ! "${compose[@]}" down; then
        notify "llama.cpp error" "Failed to stop the current model server."
        exit 1
    fi

    if env LLAMA_ENV_FILE="$env_file" "${compose[@]}" up -d; then
        notify "llama.cpp starting ($mode)" "The model server is loading in the background."
    else
        notify "llama.cpp error" "Failed to start the model server in $mode mode."
        exit 1
    fi
}

stop() {
    if "${compose[@]}" down; then
        notify "llama.cpp stopped" "The model server has been shut down."
    else
        notify "llama.cpp error" "Failed to stop the model server."
        exit 1
    fi
}

case "${1:-menu}" in
    mtp)
        start "MTP"
        ;;
    non-mtp)
        start "non-MTP"
        ;;
    stop)
        stop
        ;;
    menu)
        status="$(current_mode)"
        choice="$(printf 'Use non-MTP\nUse MTP\nStop llama.cpp\n' \
            | rofi -dmenu -i -p "llama.cpp: $status")"

        case "$choice" in
            "Use non-MTP") start "non-MTP" ;;
            "Use MTP") start "MTP" ;;
            "Stop llama.cpp") stop ;;
        esac
        ;;
    *)
        printf 'Usage: %s [menu|mtp|non-mtp|stop]\n' "$0" >&2
        exit 2
        ;;
esac
