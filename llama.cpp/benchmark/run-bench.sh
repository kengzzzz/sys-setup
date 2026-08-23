#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_DIR="${ROOT_DIR}/benchmark"
RESULTS_DIR="${BENCH_DIR}/results"
MODEL_ROOT="${ROOT_DIR}/models"
DEFAULT_COMPOSE_FILE="docker-compose.yml"
DEFAULT_COMPOSE_SERVICE="llama-server"
DEFAULT_IMAGE="llama-server"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
THREADS="$(nproc)"

resolve_env_file() {
  local env_ref="${LLAMA_ENV_FILE:-.env}"
  if [[ "${env_ref}" = /* ]]; then
    printf '%s\n' "${env_ref}"
  else
    printf '%s\n' "${ROOT_DIR}/${env_ref}"
  fi
}

ENV_FILE="$(resolve_env_file)"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "env file not found: ${ENV_FILE}" >&2
  exit 1
fi

set -a
source "${ENV_FILE}"
set +a

BENCHMARK_IMAGE="${BENCHMARK_IMAGE:-${DEFAULT_IMAGE}}"
BENCHMARK_REPETITIONS="${BENCHMARK_REPETITIONS:-3}"
BENCHMARK_N_PREDICT="${BENCHMARK_N_PREDICT:-192}"
BENCHMARK_VRAM_SAMPLE_INTERVAL="${BENCHMARK_VRAM_SAMPLE_INTERVAL:-0.1}"
BENCH_PORT="${LLAMA_ARG_PORT:-8080}"

COMPOSE_FILE="${BENCHMARK_COMPOSE_FILE:-${DEFAULT_COMPOSE_FILE}}"
[[ "${COMPOSE_FILE}" = /* ]] || COMPOSE_FILE="${ROOT_DIR}/${COMPOSE_FILE}"
COMPOSE_SERVICE="${BENCHMARK_COMPOSE_SERVICE:-${DEFAULT_COMPOSE_SERVICE}}"

if [[ -z "${LLAMA_ARG_HF_REPO:-}" ]]; then
  echo "LLAMA_ARG_HF_REPO must be set in ${ENV_FILE}" >&2
  exit 1
fi

if [[ -z "${LLAMA_ARG_SPEC_TYPE:-}" ]]; then
  echo "LLAMA_ARG_SPEC_TYPE must be set in ${ENV_FILE} for the MTP benchmark arm" >&2
  exit 1
fi

if [[ "${LLAMA_ARG_HOST:-0.0.0.0}" != "0.0.0.0" ]]; then
  echo "benchmark requires LLAMA_ARG_HOST=0.0.0.0 in ${ENV_FILE}" >&2
  exit 1
fi

hf_repo_spec="${LLAMA_ARG_HF_REPO%%:*}"
hf_variant=""
if [[ "${LLAMA_ARG_HF_REPO}" == *:* ]]; then
  hf_variant="${LLAMA_ARG_HF_REPO#*:}"
fi

hf_org="${hf_repo_spec%%/*}"
hf_repo="${hf_repo_spec#*/}"
model_snapshot_dir="${MODEL_ROOT}/hf-home/hub/models--${hf_org}--${hf_repo}/snapshots"

if [[ ! -d "${model_snapshot_dir}" ]]; then
  echo "model snapshot dir not found: ${model_snapshot_dir}" >&2
  echo "download the model first so the benchmark can reuse LLAMA_ARG_HF_REPO" >&2
  exit 1
fi

model_pattern='*.gguf'
if [[ -n "${hf_variant}" ]]; then
  model_pattern="*${hf_variant}*.gguf"
fi

mapfile -t model_candidates < <(find -L "${model_snapshot_dir}" -type f -name "${model_pattern}" | sort)
if [[ ${#model_candidates[@]} -eq 0 && -n "${hf_variant}" ]]; then
  mapfile -t model_candidates < <(find -L "${model_snapshot_dir}" -type f -name '*.gguf' ! -name 'mmproj-*' | sort)
fi

if [[ ${#model_candidates[@]} -eq 0 ]]; then
  echo "no GGUF model found under ${model_snapshot_dir}" >&2
  exit 1
fi

MODEL_PATH_ABS="${model_candidates[0]}"
MODEL_PATH_REL="${MODEL_PATH_ABS#${ROOT_DIR}/}"
if [[ "${MODEL_PATH_REL}" == "${MODEL_PATH_ABS}" ]]; then
  echo "model path is outside root dir: ${MODEL_PATH_ABS}" >&2
  exit 1
fi
MODEL_PATH_IN_CONTAINER="/${MODEL_PATH_REL}"

mkdir -p "${RESULTS_DIR}"

docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" build "${COMPOSE_SERVICE}"
docker inspect "${BENCHMARK_IMAGE}" > "${RESULTS_DIR}/image.inspect.json"

SERVER_ARGS=(-m "${MODEL_PATH_IN_CONTAINER}")
COMMON_DOCKER_ARGS=(
  --rm
  --gpus all
  --ipc host
  -p "${BENCH_PORT}:${BENCH_PORT}"
  -v "${MODEL_ROOT}:/models"
  -e "LD_LIBRARY_PATH=/usr/local/lib:/usr/local/cuda/lib64:/usr/local/nvidia/lib:/usr/local/nvidia/lib64"
)
MTP_DOCKER_ARGS=()

while IFS= read -r var_name; do
  case "${var_name}" in
    LLAMA_ARG_HF_REPO)
      continue
      ;;
    LLAMA_ARG_SPEC_*)
      MTP_DOCKER_ARGS+=( -e "${var_name}=${!var_name}" )
      ;;
    *)
      COMMON_DOCKER_ARGS+=( -e "${var_name}=${!var_name}" )
      ;;
  esac
done < <(compgen -A variable LLAMA_ARG_ | sort)

wait_for_server() {
  local url="$1"
  for _ in $(seq 1 90); do
    if curl -sf "${url}/health" > /dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "server did not start within 180s" >&2
  return 1
}

read_process_vram() {
  local host_pid="$1"
  nvidia-smi --query-compute-apps=pid,used_gpu_memory --format=csv,noheader,nounits 2>/dev/null |
    awk -F, -v target_pid="${host_pid}" '
      {
        gsub(/[[:space:]]/, "", $1)
        gsub(/[[:space:]]/, "", $2)
        if ($1 == target_pid && $2 ~ /^[0-9]+$/) {
          print $2
          exit
        }
      }
    '
}

sample_process_vram() {
  local host_pid="$1"
  local samples_file="$2"
  local value
  while kill -0 "${host_pid}" 2>/dev/null; do
    value="$(read_process_vram "${host_pid}")"
    if [[ -n "${value}" ]]; then
      printf '%s\n' "${value}" >> "${samples_file}"
    fi
    sleep "${BENCHMARK_VRAM_SAMPLE_INTERVAL}"
  done
}

active_cid=""
active_sampler_pid=""
cleanup() {
  if [[ -n "${active_sampler_pid}" ]]; then
    kill "${active_sampler_pid}" >/dev/null 2>&1 || true
    wait "${active_sampler_pid}" 2>/dev/null || true
  fi
  if [[ -n "${active_cid}" ]]; then
    docker stop "${active_cid}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

bench_variant() {
  local tag="$1"
  shift
  local variant_args=("$@")
  local samples_file="${RESULTS_DIR}/${tag}-vram-samples.txt"
  local host_pid idle_vram peak_vram

  : > "${samples_file}"
  active_cid="$(docker run -d "${COMMON_DOCKER_ARGS[@]}" "${variant_args[@]}" "${BENCHMARK_IMAGE}" "${SERVER_ARGS[@]}")"
  host_pid="$(docker inspect --format '{{.State.Pid}}' "${active_cid}")"
  sample_process_vram "${host_pid}" "${samples_file}" &
  active_sampler_pid="$!"

  wait_for_server "http://127.0.0.1:${BENCH_PORT}"
  idle_vram="$(read_process_vram "${host_pid}")"
  if [[ -z "${idle_vram}" ]]; then
    echo "could not read process VRAM for ${tag}" >&2
    return 1
  fi
  printf '%s\n' "${idle_vram}" > "${RESULTS_DIR}/${tag}-vram-idle.txt"

  "${BENCH_DIR}/mtp-bench.py" \
    --url "http://127.0.0.1:${BENCH_PORT}" \
    --out "${RESULTS_DIR}/${tag}.json" \
    --repetitions "${BENCHMARK_REPETITIONS}" \
    --n-predict "${BENCHMARK_N_PREDICT}"

  sleep "${BENCHMARK_VRAM_SAMPLE_INTERVAL}"
  kill "${active_sampler_pid}" >/dev/null 2>&1 || true
  wait "${active_sampler_pid}" 2>/dev/null || true
  active_sampler_pid=""

  peak_vram="$(awk 'max < $1 { max = $1 } END { if (max) print max }' "${samples_file}")"
  if [[ -z "${peak_vram}" ]]; then
    echo "no VRAM samples captured for ${tag}" >&2
    return 1
  fi
  printf '%s\n' "${peak_vram}" > "${RESULTS_DIR}/${tag}-vram-peak.txt"

  docker stop "${active_cid}" >/dev/null
  active_cid=""
}

echo "Benchmarking non-MTP"
bench_variant non-mtp
echo "Benchmarking MTP (${LLAMA_ARG_SPEC_TYPE})"
bench_variant mtp "${MTP_DOCKER_ARGS[@]}"

nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader > "${RESULTS_DIR}/gpu.txt"
uname -m > "${RESULTS_DIR}/arch.txt"
printf '%s\n' "${THREADS}" > "${RESULTS_DIR}/threads.txt"

python3 - "${BENCH_DIR}" "${RESULTS_DIR}" "${TIMESTAMP}" "${MODEL_PATH_IN_CONTAINER}" <<'PY'
import json
import os
import pathlib
import sys

bench_dir = pathlib.Path(sys.argv[1])
results_dir = pathlib.Path(sys.argv[2])
timestamp = sys.argv[3]
model_path = sys.argv[4]


def load_json(path):
    return json.loads(path.read_text())


def load_text(path):
    return path.read_text().strip()


def inspect_obj(data):
    if isinstance(data, list) and data:
        return data[0]
    if isinstance(data, dict):
        return data
    raise ValueError("docker inspect returned no image")


def image_ref(inspect):
    repo_digests = inspect.get("RepoDigests") or []
    if repo_digests:
        return repo_digests[0]
    repo_tags = inspect.get("RepoTags") or []
    if repo_tags:
        return repo_tags[0]
    return inspect.get("Id", "")


def image_label(inspect, key):
    return (inspect.get("Config", {}).get("Labels") or {}).get(key, "")


def result_map(data):
    return {row["name"]: row for row in data.get("results", [])}


def percent_delta(before, after):
    return ((after - before) / before) * 100.0 if before else 0.0


def fmt_percent(value):
    return f"{value:+.2f}%"


def fmt_rate(value):
    return f"{value:.3f}" if value is not None else "n/a"


image_inspect = inspect_obj(load_json(results_dir / "image.inspect.json"))
non_mtp = load_json(results_dir / "non-mtp.json")
mtp = load_json(results_dir / "mtp.json")
non_mtp_map = result_map(non_mtp)
mtp_map = result_map(mtp)
non_mtp_agg = non_mtp["aggregate"]
mtp_agg = mtp["aggregate"]

non_mtp_idle = int(load_text(results_dir / "non-mtp-vram-idle.txt"))
mtp_idle = int(load_text(results_dir / "mtp-vram-idle.txt"))
non_mtp_peak = int(load_text(results_dir / "non-mtp-vram-peak.txt"))
mtp_peak = int(load_text(results_dir / "mtp-vram-peak.txt"))

non_mtp_wall_tps = non_mtp_agg["total_predicted"] / non_mtp_agg["wall_s_total"]
mtp_wall_tps = mtp_agg["total_predicted"] / mtp_agg["wall_s_total"]
non_mtp_server_tps = non_mtp_agg["server_decode_tps"]
mtp_server_tps = mtp_agg["server_decode_tps"]

spec_settings = [
    f"`{name}={value}`"
    for name, value in sorted(os.environ.items())
    if name.startswith("LLAMA_ARG_SPEC_")
]

lines = [
    "# Non-MTP vs MTP benchmark",
    "",
    f"- Timestamp (UTC): `{timestamp}`",
    f"- Host: `{load_text(results_dir / 'arch.txt')}`",
    f"- CPU threads: `{load_text(results_dir / 'threads.txt')}`",
    f"- GPU: `{load_text(results_dir / 'gpu.txt')}`",
    f"- Model: `{model_path}`",
    f"- Image: `{image_ref(image_inspect)}`",
    f"- Image revision: `{image_label(image_inspect, 'org.opencontainers.image.revision') or 'not labeled'}`",
    "",
    "## Configuration",
    "",
    "- Both arms use the same image, model, prompts, and runtime settings.",
    "- Non-MTP removes every `LLAMA_ARG_SPEC_*` environment variable.",
    f"- MTP settings: {', '.join(spec_settings)}",
    f"- Repetitions per prompt: `{non_mtp['config']['repetitions']}`",
    f"- Predict tokens per request: `{non_mtp['config']['n_predict']}`",
    "- Temperature: `0.0`; seed: `42`; prompt cache: disabled.",
    "",
    "## Aggregate comparison",
    "",
    "| Metric | Non-MTP | MTP | Delta |",
    "| --- | ---: | ---: | ---: |",
    f"| End-to-end throughput | {non_mtp_wall_tps:,.2f} tok/s | {mtp_wall_tps:,.2f} tok/s | {fmt_percent(percent_delta(non_mtp_wall_tps, mtp_wall_tps))} |",
    f"| Server decode throughput | {non_mtp_server_tps:,.2f} tok/s | {mtp_server_tps:,.2f} tok/s | {fmt_percent(percent_delta(non_mtp_server_tps, mtp_server_tps))} |",
    f"| Total wall time | {non_mtp_agg['wall_s_total']:,.2f} s | {mtp_agg['wall_s_total']:,.2f} s | {fmt_percent(percent_delta(non_mtp_agg['wall_s_total'], mtp_agg['wall_s_total']))} |",
    f"| Idle process VRAM | {non_mtp_idle:,} MiB | {mtp_idle:,} MiB | {mtp_idle - non_mtp_idle:+,} MiB |",
    f"| Peak process VRAM | {non_mtp_peak:,} MiB | {mtp_peak:,} MiB | {mtp_peak - non_mtp_peak:+,} MiB |",
    f"| MTP draft acceptance | n/a | {fmt_rate(mtp_agg.get('aggregate_accept_rate'))} | n/a |",
    "",
    "## Per-prompt server throughput",
    "",
    "| Prompt | Non-MTP | MTP | Delta | MTP accept rate |",
    "| --- | ---: | ---: | ---: | ---: |",
]

for name, non_mtp_row in non_mtp_map.items():
    mtp_row = mtp_map[name]
    non_mtp_tps = non_mtp_row["predicted_per_second"]
    mtp_tps = mtp_row["predicted_per_second"]
    lines.append(
        f"| `{name}` | {non_mtp_tps:,.2f} tok/s | {mtp_tps:,.2f} tok/s | "
        f"{fmt_percent(percent_delta(non_mtp_tps, mtp_tps))} | {fmt_rate(mtp_row.get('accept_rate'))} |"
    )

lines.extend([
    "",
    "## Notes",
    "",
    "- End-to-end throughput includes local HTTP round-trip time; server decode throughput uses llama.cpp timing data.",
    "- VRAM is sampled from the llama-server process during model load and inference, not from total GPU usage.",
    "- The two arms run sequentially: non-MTP first, then MTP.",
    "- Raw artifacts are under `benchmark/results/`.",
])

(bench_dir / "summary.md").write_text("\n".join(lines) + "\n")
PY

echo "done - see ${BENCH_DIR}/summary.md"
