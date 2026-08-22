#!/usr/bin/env bash

set -u

project_dir="/home/keng/Documents/sys-setup/llama.cpp"
compose=(docker compose --project-directory "$project_dir")

notify() {
    notify-send --app-name="llama.cpp" "$1" "$2"
}

if [[ -n "$("${compose[@]}" ps --status running -q 2>/dev/null)" ]]; then
    if "${compose[@]}" down; then
        notify "llama.cpp stopped" "The model server has been shut down."
    else
        notify "llama.cpp error" "Failed to stop the model server."
        exit 1
    fi
else
    if "${compose[@]}" up -d; then
        notify "llama.cpp starting" "The model server is loading in the background."
    else
        notify "llama.cpp error" "Failed to start the model server."
        exit 1
    fi
fi
