# Build llama.cpp Images

- `docker compose build llama-server`

# Configure Model

- copy `./.env.example` to `./.env`
- edit `./.env`
- set `LLAMA_ARG_HF_REPO` to the Hugging Face model reference you want to use
- set `HF_TOKEN` only if the model repo is gated or private
- adjust `LLAMA_ARG_*` values in `./.env` for runtime options
- set `TS_AUTHKEY` to a Tailscale auth key for the sidecar container
- optional: set `TS_EXTRA_ARGS` if you want to pass extra `tailscale up` flags such as advertised tags
- optional: set `LLAMA_ENV_FILE` only when you want the main stack to load a different env file

# Run Server

- `docker compose up -d`
- connect to the service over the Tailscale node name `llama-server:${LLAMA_ARG_PORT}`

# Run Benchmark

- `benchmark/run-bench.sh`
- the benchmark reads the same env file as runtime config, derives the local GGUF from `LLAMA_ARG_HF_REPO`, and compares `BENCHMARK_CANDIDATE_IMAGE` against `BENCHMARK_BASELINE_IMAGE`

# Notes

- runtime services use `LLAMA_ARG_HF_REPO` from `./.env`
- downloaded models are cached under `./models/hf-home`
- the first run will download the model into the shared Hugging Face cache
- runtime arguments live in `./.env` and use `LLAMA_ARG_*`; this image patches llama.cpp to expose the configured sampling parameters through env as well
- benchmark image refs also live in `./.env`, so runtime and benchmark configuration stay in one place
- `llama-server` no longer publishes a host port; it is only reachable through the Tailscale sidecar network namespace
- the Tailscale sidecar sets `TS_ACCEPT_DNS=false`, so containers keep Docker's default DNS instead of adopting tailnet DNS settings
