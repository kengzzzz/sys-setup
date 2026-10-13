#!/usr/bin/env bash
set -euo pipefail

config=${1:-}
if [[ ! $config =~ ^[A-Za-z0-9._+-]+$ ]]; then
    echo "Usage: $0 <config name>" >&2
    exit 2
fi
log=${CS2_CONSOLE_LOG:-$HOME/.local/share/Steam/steamapps/common/Counter-Strike Global Offensive/game/csgo/console.log}
if pgrep -x cs2 > /dev/null; then
    echo 'Quit CS2 first.' >&2
    exit 1
fi
[[ -f $log ]] || { echo "No console log at $log; launch CS2 with -condebug." >&2; exit 1; }

dest="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/results/games/$config"
mkdir -p "$dest"
target="$dest/$(date +%Y%m%dT%H%M%S).log"
mv -n "$log" "$target"

ops=$(cat /sys/kernel/sched_ext/root/ops 2> /dev/null || true)
x3d=$(cat /sys/bus/platform/drivers/amd_x3d_vcache/*/amd_x3d_mode 2> /dev/null || echo n/a)
printf 'Saved %s\nsched_ext: %s%s, x3d: %s\n' "$target" "$(< /sys/kernel/sched_ext/state)" "${ops:+ ($ops)}" "$x3d"
grep -a -o 'FPS: Avg=[0-9.]*, P1=[0-9.]*' "$target" || echo 'No benchmark results in this log.' >&2
