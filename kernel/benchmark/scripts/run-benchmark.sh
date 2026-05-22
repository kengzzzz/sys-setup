#!/usr/bin/env bash
set -u

RESULTS_DIR=${RESULTS_DIR:-/results}
LABEL=${BENCH_LABEL:-local}
PROFILE=${BENCH_PROFILE:-balanced}
BASELINE_LABEL=${BENCH_BASELINE_LABEL:-cachyos-lts}
BASELINE_PROFILE=${BENCH_BASELINE_PROFILE:-balanced}
RUNS=${BENCH_RUNS:-3}
KERNEL=$(uname -r)
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
SAFE_KERNEL=$(printf '%s' "$KERNEL" | tr -c 'A-Za-z0-9._+-' '_')
SAFE_LABEL=$(printf '%s' "$LABEL" | tr -c 'A-Za-z0-9._+-' '_')
CSV="${RESULTS_DIR}/${TIMESTAMP}_${SAFE_KERNEL}_${SAFE_LABEL}.csv"
REPORT="${RESULTS_DIR}/${TIMESTAMP}_${SAFE_KERNEL}_${SAFE_LABEL}.md"
FIO_FILE="${RESULTS_DIR}/.fio-bench-${TIMESTAMP}"

mkdir -p "$RESULTS_DIR"

case "$PROFILE" in
  smoke)
    if [[ -z ${BENCH_RUNS+x} ]]; then
      RUNS=1
    fi
    STRESS_TIMEOUT=${BENCH_STRESS_TIMEOUT:-3s}
    FIO_RUNTIME=${BENCH_FIO_RUNTIME:-3}
    CYCLICTEST_DURATION=${BENCH_CYCLICTEST_DURATION:-3s}
    SCHBENCH_RUNTIME=${BENCH_SCHBENCH_RUNTIME:-5}
    ;;
  full)
    STRESS_TIMEOUT=${BENCH_STRESS_TIMEOUT:-30s}
    FIO_RUNTIME=${BENCH_FIO_RUNTIME:-30}
    CYCLICTEST_DURATION=${BENCH_CYCLICTEST_DURATION:-30s}
    SCHBENCH_RUNTIME=${BENCH_SCHBENCH_RUNTIME:-30}
    ;;
  balanced|*)
    STRESS_TIMEOUT=${BENCH_STRESS_TIMEOUT:-10s}
    FIO_RUNTIME=${BENCH_FIO_RUNTIME:-15}
    CYCLICTEST_DURATION=${BENCH_CYCLICTEST_DURATION:-10s}
    SCHBENCH_RUNTIME=${BENCH_SCHBENCH_RUNTIME:-15}
    ;;
esac

csv_field() {
  local value=${1-}
  value=${value//\"/\"\"}
  printf '"%s"' "$value"
}

csv_row() {
  local group=$1 metric=$2 unit=$3 direction=$4 run=$5 value=${6-} status=${7:-ok}
  csv_field "$TIMESTAMP"; printf ','
  csv_field "$KERNEL"; printf ','
  csv_field "$LABEL"; printf ','
  csv_field "$PROFILE"; printf ','
  csv_field "$group"; printf ','
  csv_field "$metric"; printf ','
  csv_field "$unit"; printf ','
  csv_field "$direction"; printf ','
  csv_field "$run"; printf ','
  csv_field "$value"; printf ','
  csv_field "$status"; printf '\n'
}

is_number() {
  [[ ${1-} =~ ^-?[0-9]+([.][0-9]+)?$ ]]
}

run_value() {
  local cmd=$1
  local out
  if ! out=$(bash -o pipefail -c "$cmd" 2>&1); then
    return 1
  fi
  out=$(printf '%s\n' "$out" | awk 'NF { value=$0 } END { gsub(/^[ \t]+|[ \t]+$/, "", value); print value }')
  is_number "$out" || return 1
  printf '%s' "$out"
}

record_metric() {
  local group=$1 metric=$2 unit=$3 direction=$4 cmd=$5
  local run value status

  printf 'Running %-24s' "$metric"
  for run in $(seq 1 "$RUNS"); do
    status=ok
    if ! value=$(run_value "$cmd"); then
      value=
      status=failed
    fi
    csv_row "$group" "$metric" "$unit" "$direction" "$run" "$value" "$status" >> "$CSV"
    printf ' %s:%s' "$run" "${value:-failed}"
  done
  printf '\n'
}

stress_metric_cmd() {
  local stressor=$1 workers=$2 timeout=$3
  printf "stress-ng --%s %s --timeout %s --metrics-brief 2>&1 | awk '/%s/ && !/info/ { value=\$9 } END { print value }'" \
    "$stressor" "$workers" "$timeout" "$stressor"
}

fio_cmd() {
  local rw=$1 bs=$2 field=$3
  printf "fio --name=%s --filename=%s --rw=%s --bs=%s --size=512m --runtime=%s --time_based --ioengine=libaio --iodepth=32 --numjobs=1 --group_reporting --output-format=json | jq -r '.jobs[0].%s.iops'" \
    "$rw" "$FIO_FILE" "$rw" "$bs" "$FIO_RUNTIME" "$field"
}

printf 'timestamp,kernel,label,profile,group,metric,unit,direction,run,value,status\n' > "$CSV"

printf 'Kernel benchmark\n'
printf '  kernel:   %s\n' "$KERNEL"
printf '  label:    %s\n' "$LABEL"
printf '  profile:  %s\n' "$PROFILE"
printf '  runs:     %s\n' "$RUNS"
printf '  csv:      %s\n' "$CSV"

NPROC=$(nproc)
HALF_NPROC=$(( NPROC > 1 ? NPROC / 2 : 1 ))

record_metric "Throughput" "dav1d decode" "seconds" "lower" \
  "/usr/bin/time -f '%e' dav1d -i /test.ivf --muxer null >/dev/null"
record_metric "Throughput" "x265 encode" "seconds" "lower" \
  "/usr/bin/time -f '%e' x265 --input /test.y4m --fps 60 --preset slow -o /dev/null >/dev/null"
record_metric "Throughput" "7zip" "MIPS" "higher" \
  "7z b -mmt=${NPROC} | awk '/Tot:/ { value=\$4 } END { print value }'"
record_metric "Throughput" "sysbench cpu" "events/sec" "higher" \
  "sysbench cpu --cpu-max-prime=20000 --threads=${NPROC} run | awk -F: '/events per second/ { gsub(/^[ \t]+/, \"\", \$2); print \$2 }'"
record_metric "Throughput" "stress-ng matrix" "bogo ops/sec" "higher" \
  "$(stress_metric_cmd matrix "$NPROC" "$STRESS_TIMEOUT")"
record_metric "Throughput" "openssl sha256" "bytes/sec" "higher" \
  "openssl speed -elapsed -seconds 5 sha256 2>/dev/null | awk '/^sha256 / { value=\$NF; sub(/k$/, \"\", value); print value * 1000 }'"
record_metric "Throughput" "zstd compress" "seconds" "lower" \
  "/usr/bin/time -f '%e' zstd -T${NPROC} -q -f /compress.bin -o /bench-tmp/compress.bin.zst"

record_metric "Scheduler" "stress-ng switch" "bogo ops/sec" "higher" \
  "$(stress_metric_cmd switch "$NPROC" "$STRESS_TIMEOUT")"
record_metric "Scheduler" "stress-ng futex" "bogo ops/sec" "higher" \
  "$(stress_metric_cmd futex "$NPROC" "$STRESS_TIMEOUT")"
record_metric "Scheduler" "schbench p99" "usec" "lower" \
  "schbench -m 2 -t ${NPROC} -r ${SCHBENCH_RUNTIME} 2>&1 | awk -F: '/99.0/ { gsub(/[ \t*]/, \"\", \$2); sub(/\\(.*/, \"\", \$2); value=\$2 } END { print value }'"
record_metric "Scheduler" "hackbench" "seconds" "lower" \
  "hackbench -s 100 -l 1000 -g 15 2>&1 | awk '/Time:/ { print \$2 }'"
record_metric "Scheduler" "cyclictest max" "usec" "lower" \
  "cyclictest -q -D ${CYCLICTEST_DURATION} -p 80 2>/dev/null | awk 'match(\$0, /Max:[[:space:]]*([0-9]+)/, a) { if (a[1] > max) max=a[1] } END { print max }'"

record_metric "Memory and filesystem" "stress-ng vm" "bogo ops/sec" "higher" \
  "$(stress_metric_cmd vm "$HALF_NPROC" "$STRESS_TIMEOUT")"
record_metric "Memory and filesystem" "fio randread" "IOPS" "higher" \
  "$(fio_cmd randread 4k read)"
record_metric "Memory and filesystem" "fio randwrite" "IOPS" "higher" \
  "$(fio_cmd randwrite 4k write)"
record_metric "Memory and filesystem" "fio seqread" "IOPS" "higher" \
  "$(fio_cmd read 1m read)"
record_metric "Memory and filesystem" "fio seqwrite" "IOPS" "higher" \
  "$(fio_cmd write 1m write)"

rm -f "$FIO_FILE"

python /scripts/render-report.py \
  --csv "$CSV" \
  --output "$REPORT" \
  --results-dir "$RESULTS_DIR" \
  --baseline-label "$BASELINE_LABEL" \
  --baseline-profile "$BASELINE_PROFILE"

cp "$REPORT" "${RESULTS_DIR}/latest.md"
printf 'Report: %s\n' "$REPORT"
