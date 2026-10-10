#!/usr/bin/env bash

# One marker per finished step.
STEP_DONE_DIR=${STEP_DONE_DIR:-}
# HANDLER NAME STATUS: return 0 to retry, 2 to skip, anything else exits.
STEP_FAILURE_HANDLER=${STEP_FAILURE_HANDLER:-}

step_marker() {
    printf '%s/%s' "$STEP_DONE_DIR" "$1"
}

step_done() {
    [[ -n $STEP_DONE_DIR && -e $(step_marker "$1") ]]
}

mark_step_done() {
    [[ -n $STEP_DONE_DIR ]] || return 0
    mkdir -p "$STEP_DONE_DIR"
    : >"$(step_marker "$1")"
}

run_step() {
    local name=$1
    local status decision
    shift

    if step_done "$name"; then
        log "already done: $name"
        return 0
    fi
    while true; do
        # The subshell keeps errexit on; `if step` or `step ||` would disable it.
        set +e
        (
            set -e
            "$@"
        ) </dev/null
        status=$?
        set -e
        if ((status == 0)); then
            mark_step_done "$name"
            return 0
        fi
        [[ -n $STEP_FAILURE_HANDLER ]] || exit "$status"
        decision=0
        "$STEP_FAILURE_HANDLER" "$name" "$status" || decision=$?
        case $decision in
            0) ;;
            2)
                warn "skipped: $name"
                return 0
                ;;
            *) exit "$status" ;;
        esac
    done
}
