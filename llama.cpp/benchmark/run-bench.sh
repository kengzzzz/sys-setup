#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_DIR="${ROOT_DIR}/workspace"
RESULTS_DIR="${WORKSPACE_DIR}/results"
MODEL_ROOT="${ROOT_DIR}/models"
LOCAL_IMAGE="local/llama-bench:latest"
OFFICIAL_IMAGE="ghcr.io/ggml-org/llama.cpp:full-cuda13"
BASE_CUDA_DEV_CONTAINER="nvidia/cuda@sha256:44a9504c6dfb50b1241464241b02a93871928f373de6f5a644cf5fe9f080aa63"
LLAMA_CPP_REPO="https://github.com/ggml-org/llama.cpp.git"
LLAMA_CPP_COMMIT="389ff61d77b5c71cec0cf92fe4e5d01ace80b797"
CUDA_ARCH="89-real"
CUDA_COMPRESSION_MODE="speed"
THREADS="$(nproc)"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "${RESULTS_DIR}"

MODEL_PATH_REL="$(
  find -L "${MODEL_ROOT}/hf-home/hub/models--unsloth--Qwen3.6-35B-A3B-GGUF/snapshots" \
    -name 'Qwen3.6-35B-A3B-UD-Q4_K_M.gguf' \
    | sort \
    | head -n 1 \
    | sed "s#^${ROOT_DIR}/##"
)"
if [[ -z "${MODEL_PATH_REL}" ]]; then
    echo "model file not found under ${MODEL_ROOT}" >&2
    exit 1
fi
MODEL_PATH_IN_CONTAINER="/${MODEL_PATH_REL}"

docker build \
  -f "${WORKSPACE_DIR}/Dockerfile.bench" \
  -t "${LOCAL_IMAGE}" \
  --build-arg "BASE_CUDA_DEV_CONTAINER=${BASE_CUDA_DEV_CONTAINER}" \
  --build-arg "LLAMA_CPP_REPO=${LLAMA_CPP_REPO}" \
  --build-arg "LLAMA_CPP_COMMIT=${LLAMA_CPP_COMMIT}" \
  --build-arg "CUDA_ARCH=${CUDA_ARCH}" \
  --build-arg "CUDA_COMPRESSION_MODE=${CUDA_COMPRESSION_MODE}" \
  "${ROOT_DIR}"

docker pull "${OFFICIAL_IMAGE}"

docker inspect "${LOCAL_IMAGE}" > "${RESULTS_DIR}/local-image.inspect.json"
docker inspect "${OFFICIAL_IMAGE}" > "${RESULTS_DIR}/official-image.inspect.json"

COMMON_DOCKER_ARGS=(
  --rm
  --gpus all
  --ipc host
  --user "$(id -u):$(id -g)"
  -e "LD_LIBRARY_PATH=/app:/usr/local/cuda/lib64:/usr/local/nvidia/lib:/usr/local/nvidia/lib64"
  -v "${MODEL_ROOT}:/models"
  -w /models
)

docker run "${COMMON_DOCKER_ARGS[@]}" "${LOCAL_IMAGE}" --help > "${RESULTS_DIR}/local-help.txt"
docker run "${COMMON_DOCKER_ARGS[@]}" --entrypoint /app/llama-bench "${OFFICIAL_IMAGE}" --help > "${RESULTS_DIR}/official-help.txt"

LOCAL_BENCH_ARGS=(
  -m "${MODEL_PATH_IN_CONTAINER}"
  -p 512
  -n 128
  -b 2048
  -ub 512
  -ngl 999
  -fa 1
  -ctk q8_0
  -ctv q8_0
  -ncmoe 18
  -mmp 0
  -t "${THREADS}"
  -r 5
  -o json
  --progress
)

docker run "${COMMON_DOCKER_ARGS[@]}" "${LOCAL_IMAGE}" "${LOCAL_BENCH_ARGS[@]}" > "${RESULTS_DIR}/local.json"
docker run "${COMMON_DOCKER_ARGS[@]}" --entrypoint /app/llama-bench "${OFFICIAL_IMAGE}" "${LOCAL_BENCH_ARGS[@]}" > "${RESULTS_DIR}/official.json"

nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader > "${RESULTS_DIR}/gpu.txt"
uname -m > "${RESULTS_DIR}/arch.txt"
nproc > "${RESULTS_DIR}/threads.txt"

python3 - "${WORKSPACE_DIR}" "${RESULTS_DIR}" "${TIMESTAMP}" "${MODEL_PATH_IN_CONTAINER}" <<'PY'
import json
import pathlib
import sys

workspace_dir = pathlib.Path(sys.argv[1])
results_dir = pathlib.Path(sys.argv[2])
timestamp = sys.argv[3]
model_path = sys.argv[4]

def load_json(path: pathlib.Path):
    with path.open() as fh:
        return json.load(fh)

def load_text(path: pathlib.Path) -> str:
    return path.read_text().strip()

local_inspect = load_json(results_dir / "local-image.inspect.json")[0]
official_inspect = load_json(results_dir / "official-image.inspect.json")[0]
local_results = load_json(results_dir / "local.json")
official_results = load_json(results_dir / "official.json")
gpu_line = load_text(results_dir / "gpu.txt")
arch = load_text(results_dir / "arch.txt")
threads = load_text(results_dir / "threads.txt")

def get_label(inspect, key):
    return (inspect.get("Config", {}).get("Labels") or {}).get(key, "")

def image_ref(inspect):
    repo_digests = inspect.get("RepoDigests") or []
    if repo_digests:
        return repo_digests[0]
    repo_tags = inspect.get("RepoTags") or []
    if repo_tags:
        return repo_tags[0]
    return inspect.get("Id", "")

def normalize_rows(payload):
    if isinstance(payload, dict):
        for key in ("results", "benchmarks", "data"):
            value = payload.get(key)
            if isinstance(value, list):
                payload = value
                break
    if not isinstance(payload, list):
        raise SystemExit(f"unexpected benchmark JSON shape: {type(payload)!r}")

    rows = {}
    for row in payload:
        test = row.get("test") or row.get("name") or ""
        if not test:
            n_prompt = int(row.get("n_prompt") or 0)
            n_gen = int(row.get("n_gen") or 0)
            if n_prompt and not n_gen:
                test = f"pp{n_prompt}"
            elif n_gen and not n_prompt:
                test = f"tg{n_gen}"
        if not test:
            continue
        samples_ns = row.get("samples_ns") or row.get("samples") or []
        samples_ts = row.get("samples_ts") or []
        avg_ns = row.get("avg_ns")
        if avg_ns is None and samples_ns:
            avg_ns = sum(samples_ns) / len(samples_ns)
        if avg_ns is None:
            raise SystemExit(f"missing avg_ns for benchmark row {row}")
        avg_ts = row.get("avg_ts")
        if avg_ts is None and samples_ts:
            avg_ts = sum(samples_ts) / len(samples_ts)
        if avg_ts is None:
            avg_ts = 1e9 / float(avg_ns)
        rows[test] = {
            "avg_ns": float(avg_ns),
            "avg_ts": float(avg_ts),
            "samples": len(samples_ns),
        }
    return rows

local_rows = normalize_rows(local_results)
official_rows = normalize_rows(official_results)

wanted = ["pp512", "tg128"]
for name in wanted:
    if name not in local_rows or name not in official_rows:
        raise SystemExit(f"missing benchmark row {name}")

def fmt_tps(value):
    return f"{value:,.2f} tok/s"

def fmt_pct(value):
    sign = "+" if value >= 0 else ""
    return f"{sign}{value:.2f}%"

lines = [
    "# llama.cpp benchmark summary",
    "",
    f"- Timestamp (UTC): `{timestamp}`",
    f"- Host: `{arch}`",
    f"- CPU threads: `{threads}`",
    f"- GPU: `{gpu_line}`",
    f"- Model: `{model_path}`",
    f"- Local image: `{image_ref(local_inspect)}`",
    f"- Local image revision: `{get_label(local_inspect, 'org.opencontainers.image.revision')}`",
    f"- Official image: `{image_ref(official_inspect)}`",
    f"- Official image revision: `{get_label(official_inspect, 'org.opencontainers.image.revision') or 'not labeled'}`",
    "",
    "## Benchmark setup",
    "",
    "- Tool: `llama-bench`",
    "- Prompt tokens: `512`",
    "- Generation tokens: `128`",
    "- Batch size: `2048`",
    "- Micro-batch size: `512`",
    "- GPU layers: `999`",
    "- Flash attention: `on`",
    "- KV cache types: `q8_0 / q8_0`",
    "- CPU MoE threads: `18`",
    "- mmap: `off`",
    "- Repetitions: `5`",
    "",
    "## Results",
    "",
    "| Test | Local | Official | Delta vs official |",
    "| --- | ---: | ---: | ---: |",
]

for name in wanted:
    local_tps = local_rows[name]["avg_ts"]
    official_tps = official_rows[name]["avg_ts"]
    delta_pct = ((local_tps - official_tps) / official_tps) * 100.0
    lines.append(
        f"| `{name}` | {fmt_tps(local_tps)} | {fmt_tps(official_tps)} | {fmt_pct(delta_pct)} |"
    )

lines.extend([
    "",
    "## Notes",
    "",
    "- This is an inference benchmark, not a `llama-server` throughput or concurrency benchmark.",
    "- `.env.example` settings that do not map to `llama-bench` were not applied: `LLAMA_ARG_HOST`, `LLAMA_ARG_PORT`, `LLAMA_ARG_N_PARALLEL`, `LLAMA_ARG_CTX_SIZE`.",
    "- Raw artifacts: `workspace/results/local.json`, `workspace/results/official.json`, and both `docker inspect` outputs.",
])

(workspace_dir / "summary.md").write_text("\n".join(lines) + "\n")
PY
