#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=check-profile-kernel.sh
source "$(dirname "$0")/check-profile-kernel.sh"

target=${PROPELLER_DENSITY:-50}
plateau=${PROPELLER_PLATEAU:-2}
max_minutes=${PROPELLER_MAX_MINUTES:-60}
number='^[0-9]+([.][0-9]+)?$'
if [[ ! $target =~ $number || ! $plateau =~ $number || ! $max_minutes =~ ^[0-9]+$ ]] || ((max_minutes < 10)); then
    echo 'PROPELLER_DENSITY and PROPELLER_PLATEAU must be numbers and PROPELLER_MAX_MINUTES an integer of at least 10.' >&2
    exit 2
fi
case ${PROPELLER_SMOKE:-no} in
    yes|1) smoke=yes cycle_seconds=20 min_cycles=1 max_cycles=2 ;;
    no|0) smoke=no cycle_seconds=300 min_cycles=2 max_cycles=$((max_minutes / 5)) ;;
    *) echo 'PROPELLER_SMOKE must be yes/no or 1/0.' >&2; exit 2 ;;
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
    rm -f /profiles/.propeller_{cc,ld}_profile.txt.new
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

# Converts comma-separated perf files into <prefix>_{cc,ld}_profile.txt and
# prints the converter's hot basic block count.
convert() {
    local perfdata=$1 prefix=$2 blocks
    # ThinLTO matches cc entries per module; without names, same-named statics collide.
    if ! generate_propeller_profiles --binary="$profile_binary" --profile="$perfdata" \
        --propeller_options='output_module_name: true' \
        --cc_profile="${prefix}_cc_profile.txt" --ld_profile="${prefix}_ld_profile.txt" \
        > "$prefix.log" 2>&1; then
        tail -n 20 "$prefix.log" >&2
        return 1
    fi
    if [[ ! -s ${prefix}_ld_profile.txt ]]; then
        echo "No hot functions in $perfdata; perf samples did not map onto this vmlinux." >&2
        return 1
    fi
    blocks=$(sed -n 's/^\([0-9]*\) hot basic blocks found in profiles\.$/\1/p' "$prefix.log")
    [[ -n $blocks ]] || { echo "No hot basic block count in $prefix.log" >&2; return 1; }
    echo "$blocks"
}

describe() {
    printf 'cc %d functions, %d module names, %d clone paths; ld %d symbols' \
        "$(grep -c '^f ' "${1}_cc_profile.txt" || true)" \
        "$(grep -c '^m ' "${1}_cc_profile.txt" || true)" \
        "$(grep -c '^p' "${1}_cc_profile.txt" || true)" "$(wc -l < "${1}_ld_profile.txt")"
}

check_profile_kernel propeller
# llvm-profgen writes its perf script dump to the working directory.
cd /build

# perf cannot map kernel samples when kallsyms addresses are hidden from root.
if (($(< "$kptr") > 1)); then
    saved_kptr=$(< "$kptr")
    echo 1 > "$kptr"
    printf 'kernel.kptr_restrict: %s -> 1 while profiling (restored on exit)\n' "$saved_kptr"
fi

echo 'Preflight: perf branch sampling, generate_propeller_profiles and llvm-profgen'
"${record[@]}" -q -o preflight.data -- dd if=/dev/zero of=/dev/null bs=1 count=2000000 status=none
convert preflight.data preflight > /dev/null
density=$(profgen preflight.afdo --perfdata=preflight.data --profile-density-threshold=0)
if ! compare "${density:-0}" '>' 0; then
    echo 'Preflight profile is empty; perf samples did not map onto this vmlinux.' >&2
    exit 1
fi
printf 'Preflight: %s\n' "$(describe preflight)"
rm preflight.data preflight.afdo preflight.log preflight_{cc,ld}_profile.txt
echo 'Preflight: workload loads'
bash /scripts/run-autofdo-workload.sh 20

cycles=0
planned=$min_cycles
data=()
blocks=0
measured=0
growth=100
while true; do
    while ((cycles < planned)); do
        cycles=$((cycles + 1))
        printf '\nCycle %d (planned %d, max %d)\n' "$cycles" "$planned" "$max_cycles"
        "${record[@]}" -o "cycle$cycles.data" -- bash /scripts/run-autofdo-workload.sh "$cycle_seconds" &
        perf_pid=$!
        wait "$perf_pid"
        perf_pid=
        data+=("cycle$cycles.data")
        profgen cycle.afdo --perfdata="cycle$cycles.data" --profile-density-threshold=0 > /dev/null
        if [[ -f total.afdo ]]; then
            llvm-profdata merge --sample total.afdo cycle.afdo -o merged.afdo
            mv merged.afdo total.afdo
            rm cycle.afdo
        else
            mv cycle.afdo total.afdo
        fi
        # Each conversion rereads every cycle; only the last two planned ones feed the plateau check.
        if ((cycles >= planned - 1)); then
            previous=$blocks
            since=$measured
            blocks=$(IFS=,; convert "${data[*]}" propeller)
            measured=$cycles
            growth=$(awk -v b="$blocks" -v p="$previous" 'BEGIN { printf "%.1f", p ? (b - p) * 100 / p : 100 }')
            printf 'Profile after cycle %d: %d hot basic blocks (+%s%% since cycle %d), %s\n' \
                "$cycles" "$blocks" "$growth" "$since" "$(describe propeller)"
        fi
    done
    density=$(profgen density.afdo --llvm-sample-profile=total.afdo --profile-density-threshold="$target")
    rm density.afdo
    printf 'After %s: density %s (target %s), hot basic blocks +%s%% in the last cycle (target < %s%%)\n' \
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

test -s propeller_cc_profile.txt || { echo 'Propeller cc profile is empty.' >&2; exit 1; }
echo 'Hottest functions:'
head -n 5 propeller_ld_profile.txt
echo 'Kernel samples in the last cycle by command and binary/module (interrupt work can be attributed to the interrupted task):'
perf report -i "cycle$cycles.data" --stdio --header --sort comm,dso --show-nr-samples --percent-limit 1 || true

if [[ $smoke == yes ]]; then
    echo 'Smoke run passed; Propeller profiles unchanged.'
    exit 0
fi
for kind in cc ld; do
    install -m 0644 -o "$(stat -c %u /profiles)" -g "$(stat -c %g /profiles)" \
        "propeller_${kind}_profile.txt" "/profiles/.propeller_${kind}_profile.txt.new"
done
for kind in cc ld; do
    mv "/profiles/.propeller_${kind}_profile.txt.new" "/profiles/propeller_${kind}_profile.txt"
done
printf 'Recorded %s of workload; %d hot basic blocks.\n' "$(duration $((cycles * cycle_seconds)))" "$blocks"
sha256sum /profiles/propeller_{cc,ld}_profile.txt
