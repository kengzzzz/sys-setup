#!/usr/bin/env bash
set -euo pipefail

seconds=${1:-}
if [[ ! $seconds =~ ^[0-9]+$ ]] || ((seconds < 20)); then
    echo "Usage: $0 <cycle seconds, at least 20>" >&2
    exit 2
fi
game=$((seconds / 4))
call=$((seconds * 3 / 20))
build=$((seconds / 4))
files=$((seconds * 3 / 20))
system=$((seconds - game - call - build - files))

net=https://speed.cloudflare.com
# speed.cloudflare.com answers sustained large downloads with HTTP 429.
iso=https://fastly.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso
clip=/usr/local/share/autofdo/1440p60.mp4
camera_dev=
for node in /sys/class/video4linux/video*; do
    [[ -r $node/name && $(< "$node/name") == 'Broadcast Camera' ]] && camera_dev=/dev/${node##*/}
done
# Default source is the Broadcast Mic. Playback is zeros at volume 0 into the default sink.
record=(pw-cat --record --raw --rate=48000 --channels=1 --format=f32 --latency=10ms /dev/null)
playback=(pw-cat --playback --raw --rate=48000 --channels=2 --format=s16 --latency=10ms
    --volume=0 /dev/zero)

check() {
    local problem=$1
    shift
    "$@" > /dev/null 2>&1 || { echo "AutoFDO workload: $problem" >&2; exit 1; }
}

# A device client must still be running when the probe ends.
probe() {
    local problem=$1 status=0
    shift
    timeout 2 "$@" > /dev/null 2>&1 || status=$?
    ((status == 124)) || { echo "AutoFDO workload: $problem" >&2; exit 1; }
}

# One-time setup on the Docker volume; the first call is the unrecorded preflight.
if [[ ! -e /scratch/.ready ]]; then
    [[ -n $camera_dev ]] || { echo 'AutoFDO workload: no Broadcast Camera; start broadcast-linux.' >&2; exit 1; }
    check 'NVDEC decoding failed; check the NVIDIA Container Toolkit.' \
        ffmpeg -nostdin -hwaccel cuda -hwaccel_output_format cuda -i "$clip" -frames:v 30 -f null -
    check 'PipeWire is unreachable through the mounted socket.' timeout 5 pw-dump
    probe 'cannot record from the default PipeWire source.' "${record[@]}"
    probe 'cannot play to the default PipeWire sink.' "${playback[@]}"
    check "no frame from Broadcast Camera ($camera_dev); is broadcast-linux running?" \
        timeout 10 ffmpeg -nostdin -f v4l2 -i "$camera_dev" -frames:v 1 -f null -
    check "$net is unreachable." curl -fsS --max-time 15 -o /dev/null "$net/__down?bytes=1000"
    check "$iso is unreachable." curl -fsS --max-time 15 -r 0-999999 -o /dev/null "$iso"
    rm -rf /scratch/linux.tmp
    cp -a /usr/src/linux /scratch/linux.tmp
    mv /scratch/linux.tmp /scratch/linux
    make -s -C /scratch/linux O=/scratch/kbuild defconfig
    head -c 25000000 /dev/zero > /scratch/upload.bin
    touch /scratch/.ready
fi

# Loop wrappers re-signal their process group on exit: a child started just after
# timeout's group signal would otherwise outlive the loop.
stop_group() {
    trap '' INT TERM
    kill -TERM 0 2>/dev/null
    exit 130
}

kernel_build() {
    local make=(make -s -C /scratch/linux O=/scratch/kbuild)
    trap stop_group INT TERM
    # make reports every sub-make it interrupts; show its output only on a real failure.
    while "${make[@]}" -j"$(nproc)" 2> /scratch/kbuild.log; do
        "${make[@]}" clean
    done
    tail -n 20 /scratch/kbuild.log >&2
    return 1
}

tree_scan() {
    trap stop_group INT TERM
    while rg -uuu -c sched /scratch/linux > /dev/null && find /scratch/linux -size +1M > /dev/null; do
        :
    done
    return 1
}

# --laptop keeps cyclictest from pinning the host's /dev/cpu_dma_latency to 0.
timer_wakeups() {
    exec cyclictest --laptop -q -t -i 1000 -d 0 --policy=other > /dev/null 2>&1
}

# Device and network readers restart after a broadcast-linux restart or a
# dropped connection instead of failing a recorded cycle; repeated failures
# (e.g. a rate-limited server) back off up to a minute.
persist() {
    local delay=2
    trap stop_group INT TERM
    while true; do
        if "$@"; then
            delay=2
        else
            sleep "$delay"
            delay=$((delay < 32 ? delay * 2 : 64))
        fi
    done
}
export -f stop_group kernel_build tree_scan timer_wakeups persist

keep=(bash -c 'persist "$@"' persist)
# With -stream_loop, ffmpeg can log thousands of demuxer errors while it stops.
video=(ffmpeg -nostdin -hide_banner -loglevel fatal -hwaccel cuda -hwaccel_output_format cuda
    -re -stream_loop -1 -i "$clip" -an -f null -)
timers=(bash -c timer_wakeups)
download=("${keep[@]}" curl -fsS --limit-rate 1M -o /dev/null "$iso")
gpu=(autofdo-gpu-load 15 120 600 2560 1440)
mic=("${keep[@]}" "${record[@]}")
speaker=("${keep[@]}" "${playback[@]}")
# Frames are discarded; v4l2loopback's occasional duplicate timestamps are not errors.
camera=("${keep[@]}" ffmpeg -nostdin -hide_banner -loglevel fatal -f v4l2 -i "$camera_dev" -an
    -fps_mode passthrough -f null -)
upload=("${keep[@]}" curl -fsS --limit-rate 300K -o /dev/null --data-binary @/scratch/upload.bin "$net/__up")
compile=(bash -c kernel_build)
scan=(bash -c tree_scan)
stress=(stress-ng --temp-path=/scratch --no-rand-seed --timeout=1h)
disk=("${stress[@]}" --hdd=1 --hdd-bytes=1G --hdd-opts=wr-seq,rd-rnd,fsync --iomix=1 --dentry=1)
# Host networking: keep stress-ng off its default TCP 22000 (Syncthing) and UDP 7000.
kernel=("${stress[@]}" --fork=1 --mmap=1 --futex=2 --switch=2 --sock=1 --sock-port=47000
    --udp=1 --udp-port=47100 --epoll=1 --sockpair=1 --sockfd=1)

loads=()
declare -A labels=()
stop_loads() {
    local pid
    for pid in "${loads[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
    for pid in "${loads[@]}"; do wait "$pid" 2>/dev/null || true; done
    loads=()
}
trap stop_loads EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# pid: host makes loads host processes. timeout leads its own process group and
# signals all of it (compilers, stressor workers) at the deadline or on TERM.
phase() {
    local name=$1 seconds=$2 load finished pid status remaining start=$SECONDS
    shift 2
    printf '[%(%T)T] %s for %ss\n' -1 "$name" "$seconds"
    for load in video timers download "$@"; do
        local -n argv=$load
        timeout --signal=INT --kill-after=30s "${seconds}s" "${argv[@]}" &
        loads+=("$!")
        labels[$!]=$load
        unset -n argv
    done
    while ((${#loads[@]})); do
        status=0
        wait -n -p finished "${loads[@]}" || status=$?
        if ((status == 137 && SECONDS - start >= seconds)); then
            echo "AutoFDO workload: $name/${labels[$finished]} needed SIGKILL at the phase deadline" >&2
        elif ((status != 124)); then
            echo "AutoFDO workload: $name/${labels[$finished]:-?} stopped early (exit $status)" >&2
            exit 1
        fi
        remaining=()
        for pid in "${loads[@]}"; do
            [[ $pid == "$finished" ]] || remaining+=("$pid")
        done
        loads=("${remaining[@]}")
    done
}

phase game "$game" gpu mic speaker
phase call "$call" camera mic speaker upload
phase build "$build" compile
phase files "$files" disk scan
phase system "$system" kernel
