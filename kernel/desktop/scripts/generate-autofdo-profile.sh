#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=check-profile-kernel.sh
source "$(dirname "$0")/check-profile-kernel.sh"

target=${AUTOFDO_DENSITY:-50}
plateau=${AUTOFDO_PLATEAU:-2}
max_minutes=${AUTOFDO_MAX_MINUTES:-60}
number='^[0-9]+([.][0-9]+)?$'
if [[ ! $target =~ $number || ! $plateau =~ $number || ! $max_minutes =~ ^[0-9]+$ ]] || ((max_minutes < 10)); then
    echo 'AUTOFDO_DENSITY and AUTOFDO_PLATEAU must be numbers and AUTOFDO_MAX_MINUTES an integer of at least 10.' >&2
    exit 2
fi
case ${AUTOFDO_SMOKE:-no} in
    yes|1) smoke=yes cycle_seconds=20 min_cycles=1 max_cycles=2 ;;
    no|0) smoke=no cycle_seconds=300 min_cycles=2 max_cycles=$((max_minutes / 5)) ;;
    *) echo 'AUTOFDO_SMOKE must be yes/no or 1/0.' >&2; exit 2 ;;
esac

record=(perf record --pfm-events RETIRED_TAKEN_BRANCH_INSTRUCTIONS:k -a -N -b -c 500009)
kptr=/proc/sys/kernel/kptr_restrict
saved_kptr=
perf_pid=
cleanup() {
    if [[ -n $perf_pid ]]; then
        kill -TERM "$perf_pid" 2>/dev/null || true
        wait "$perf_pid" || true
    fi
    [[ -z $saved_kptr ]] || echo "$saved_kptr" > "$kptr"
    rm -f /profiles/.kernel.afdo.new
    [[ -z ${profile_extract:-} ]] || rm -rf "$profile_extract"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

compare() { awk -v a="$1" -v b="$3" "BEGIN { exit !(a $2 b) }"; }
duration() { printf '%dm%02ds' $(($1 / 60)) $(($1 % 60)); }

# Prints llvm-profgen's hot-function profile density (its "enough samples" metric).
profgen() {
    local output=$1
    shift
    llvm-profgen --kernel --binary="$profile_binary" --show-density "$@" -o "$output" |
        sed -n 's/^Functions with density >= \([0-9.]*\) .*/\1/p'
}

check_profile_kernel autofdo
# llvm-profgen writes its perf script dump to the working directory.
cd /build

# perf cannot map kernel samples when kallsyms addresses are hidden from root.
if (($(< "$kptr") > 1)); then
    saved_kptr=$(< "$kptr")
    echo 1 > "$kptr"
    printf 'kernel.kptr_restrict: %s -> 1 while profiling (restored on exit)\n' "$saved_kptr"
fi

echo 'Preflight: perf branch sampling and llvm-profgen'
"${record[@]}" -q -o preflight.data -- dd if=/dev/zero of=/dev/null bs=1 count=2000000 status=none
density=$(profgen preflight.afdo --perfdata=preflight.data --profile-density-threshold=0)
if ! compare "${density:-0}" '>' 0; then
    echo 'Preflight profile is empty; perf samples did not map onto this vmlinux.' >&2
    exit 1
fi
rm preflight.data preflight.afdo
echo 'Preflight: workload loads'
bash /scripts/run-autofdo-workload.sh 20

cycles=0
planned=$min_cycles
entries=0
growth=100
while true; do
    while ((cycles < planned)); do
        cycles=$((cycles + 1))
        printf '\nCycle %d (planned %d, max %d)\n' "$cycles" "$planned" "$max_cycles"
        "${record[@]}" -o cycle.data -- bash /scripts/run-autofdo-workload.sh "$cycle_seconds" &
        perf_pid=$!
        wait "$perf_pid"
        perf_pid=
        profgen cycle.afdo --perfdata=cycle.data --profile-density-threshold=0 > /dev/null
        rm cycle.data
        if [[ -f total.afdo ]]; then
            llvm-profdata merge --sample total.afdo cycle.afdo -o merged.afdo
            mv merged.afdo total.afdo
            rm cycle.afdo
        else
            mv cycle.afdo total.afdo
        fi
        # Coverage is counted in text-profile lines (functions + sampled source
        # lines): byte size also creeps up as varint-encoded counts get larger.
        previous=$entries
        entries=$(llvm-profdata merge --sample --text total.afdo | wc -l)
        growth=$(awk -v e="$entries" -v p="$previous" 'BEGIN { printf "%.1f", p ? (e - p) * 100 / p : 100 }')
        awk -v n="$cycles" -v e="$entries" -v g="$growth" -v s="$(stat -c %s total.afdo)" \
            'BEGIN { printf "Profile after cycle %d: %d entries (+%s%%), %.2f MB\n", n, e, g, s / 1048576 }'
    done
    density=$(profgen density.afdo --llvm-sample-profile=total.afdo --profile-density-threshold="$target")
    rm density.afdo
    printf 'After %s: density %s (target %s), coverage +%s%% in the last cycle (target < %s%%)\n' \
        "$(duration $((cycles * cycle_seconds)))" "${density:-?}" "$target" "$growth" "$plateau"
    compare "${density:-0}" '>' 0 || { echo 'Merged profile is empty.' >&2; exit 1; }
    dense=no
    compare "$density" '>=' "$target" && dense=yes
    [[ $dense == yes ]] && compare "$growth" '<' "$plateau" && break
    if ((cycles >= max_cycles)); then
        echo "Stopping at the $(duration $((cycles * cycle_seconds))) cap before both targets were met." >&2
        break
    fi
    if [[ $dense == yes ]]; then
        planned=$((cycles + 1))
    else
        # Density grows roughly linearly with recording time.
        planned=$(awk -v n="$cycles" -v d="$density" -v t="$target" -v max="$max_cycles" 'BEGIN {
            want = n * t / d
            want = want == int(want) ? want : int(want) + 1
            if (want <= n) want = n + 1
            print (want > max ? max : want)
        }')
    fi
done

if [[ $smoke == yes ]]; then
    echo 'Smoke run passed; profiles/kernel.afdo unchanged.'
    exit 0
fi
install -m 0644 -o "$(stat -c %u /profiles)" -g "$(stat -c %g /profiles)" total.afdo /profiles/.kernel.afdo.new
mv /profiles/.kernel.afdo.new /profiles/kernel.afdo
printf 'Recorded %s of workload; %d profile entries.\n' "$(duration $((cycles * cycle_seconds)))" "$entries"
sha256sum /profiles/kernel.afdo
