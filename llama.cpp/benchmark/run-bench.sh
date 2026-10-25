#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_DIR="${ROOT_DIR}/benchmark"
RESULTS_DIR="${BENCHMARK_RESULTS_DIR:-${BENCH_DIR}/results}"
SERVICE=llama-server
PORT=18080

env_ref="${LLAMA_ENV_FILE:-.env}"
[[ "${env_ref}" = /* ]] || env_ref="${ROOT_DIR}/${env_ref}"
[[ -f "${env_ref}" ]] || { echo "env file not found: ${env_ref}" >&2; exit 1; }
set -a
source "${env_ref}"
set +a

IMAGE="${BENCHMARK_IMAGE:-llama-server}"
read -r -a ARMS <<< "${BENCHMARK_ARMS:-default mtp}"
compose=(docker compose --project-directory "${ROOT_DIR}" -f "${ROOT_DIR}/docker-compose.yml")

if [[ -n "$(docker ps -q -f name="^${SERVICE}$")" ]]; then
  echo "stop the running ${SERVICE} container first (llama-toggle.sh stop)" >&2
  exit 1
fi

mkdir -p "${RESULTS_DIR}"
tmp_dir="$(mktemp -d)"
cid=""
cleanup() {
  [[ -z "${cid}" ]] || docker rm -f "${cid}" >/dev/null 2>&1 || true
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT INT TERM

[[ "${BENCHMARK_SKIP_BUILD:-0}" == 1 ]] || "${compose[@]}" build "${SERVICE}"

service_config() {
  local env_file="$1"
  LLAMA_ENV_FILE="${env_file}" "${compose[@]}" config --format json | python3 -c '
import json, sys
s = json.load(sys.stdin)["services"]["'"${SERVICE}"'"]
env = {k: v for k, v in s["environment"].items() if not k.startswith(("TS_", "BENCHMARK_"))}
env["LLAMA_ARG_PORT"] = "'"${PORT}"'"
with open(sys.argv[1], "w") as f:
    f.write("".join(f"{k}={v}\n" for k, v in sorted(env.items())))
with open(sys.argv[2], "w") as f:
    f.write("\n".join(s.get("command") or []))
' "${tmp_dir}/env" "${tmp_dir}/command"
}

wait_ready() {
  for _ in $(seq 1 150); do
    curl -sf "http://127.0.0.1:${PORT}/health" > /dev/null 2>&1 && return 0
    [[ "$(docker inspect -f '{{.State.Running}}' "${cid}" 2>/dev/null)" == true ]] || break
    sleep 2
  done
  docker logs "${cid}" 2>&1 | tail -20 >&2
  echo "server did not become ready" >&2
  return 1
}

for arm in "${ARMS[@]}"; do
  env_file="${env_ref}"
  if [[ "${arm}" != default ]]; then
    overlay="${ROOT_DIR}/${arm}.env"
    [[ -f "${overlay}" ]] || { echo "no overlay for arm ${arm}: ${overlay}" >&2; exit 1; }
    cat "${env_ref}" "${overlay}" > "${tmp_dir}/${arm}.env"
    env_file="${tmp_dir}/${arm}.env"
  fi
  service_config "${env_file}"
  mapfile -t command < "${tmp_dir}/command"
  { grep -v '^HF_TOKEN=' "${tmp_dir}/env"; printf 'command=%s\n' "${command[*]}"; } > "${RESULTS_DIR}/${arm}.env"

  echo "== ${arm} (${IMAGE})"
  cid="$(docker run -d --gpus all --ipc host --ulimit memlock=-1 --ulimit stack=67108864 \
    --user "${LOCAL_UID:-1000}:${LOCAL_GID:-1000}" -w /models \
    -p "127.0.0.1:${PORT}:${PORT}" -v "${ROOT_DIR}/models:/models" \
    --env-file "${tmp_dir}/env" "${IMAGE}" "${command[@]}")"
  wait_ready
  docker logs "${cid}" > "${RESULTS_DIR}/${arm}.server.log" 2>&1
  python3 -I "${BENCH_DIR}/agent-bench.py" --url "http://127.0.0.1:${PORT}" \
    --pid "$(docker inspect -f '{{.State.Pid}}' "${cid}")" \
    --out "${RESULTS_DIR}/${arm}.json" ${BENCHMARK_FLAGS:-}
  docker rm -f "${cid}" > /dev/null
  cid=""
done

docker image inspect "${IMAGE}" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' \
  > "${RESULTS_DIR}/image-revision.txt"
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader > "${RESULTS_DIR}/gpu.txt"
python3 -I "${BENCH_DIR}/agent-bench.py" --report "${BENCH_DIR}/summary.md" --results-dir "${RESULTS_DIR}" "${ARMS[@]}"
echo "done - see ${BENCH_DIR}/summary.md"
