# Build llama.cpp Images

- install the NVIDIA driver plus `nvidia-container-toolkit` on the Docker host;
  the Compose services request `gpus: all`
- verify GPU containers before building with
  `docker run --rm --gpus all nvidia/cuda:13.4.3-base-ubuntu24.04 nvidia-smi`
- after replacing the GPU or driver, regenerate a stale CDI spec with
  `sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml` if `nvidia-smi`
  works in Docker but CUDA initialization fails
- `docker compose build llama-server`
- `docker-compose.yml` pins the llama.cpp commit and the CUDA image digest; the
  build targets only `sm_120a` (RTX 50 series) and compiles only the
  FlashAttention K/V kernels listed in `GGML_CUDA_FA_QUANTS`
- the image also ships `llama-bench` for kernel-level sweeps

# Configure Model

- copy `./.env.example` to `./.env`
- edit `./.env`
- the model is `ISTA-DASLab/Qwen3.8-27B-GSQ-RCO-GGUF`, file
  `Qwen3.8-27B-GSQ-RCO-IQ3_XXS-mtp.gguf`. The `-mtp` build adds the MTP head,
  and llama.cpp loads it only when MTP is enabled, so the same file serves both
  modes without costing VRAM in the default one
- pin a different file with `LLAMA_ARG_HF_FILE`; a bare quant tag in
  `LLAMA_ARG_HF_REPO` matches both the `-mtp` and plain files
- `LLAMA_ARG_OFFLINE=1` serves the cached file without checking the repo, so an
  upstream re-upload cannot replace the model. Set it to `0` for the first
  download or after changing the model
- the server answers as `qwen3.8-27b` (`LLAMA_ARG_ALIAS`)
- defaults: 128K context, Q4_0 K/V cache, ubatch 512, MTP off, vision
  projector kept on the CPU, 16 GiB host-RAM prompt cache
- `mtp.env` holds the MTP settings and is layered over `.env` in MTP mode, where
  it can override any `.env` value. It lowers the context to 80K, which leaves
  as much VRAM free as the default mode does at 128K
- `--slot-prompt-similarity` has no env variable, so it is set in the Compose
  `command`; keep it there when changing other options
- set `HF_TOKEN` only if the model repo is gated or private
- set `TS_AUTHKEY` to a Tailscale auth key for the sidecar container
- optional: set `TS_EXTRA_ARGS` if you want to pass extra `tailscale up` flags such as advertised tags
- optional: set `LLAMA_ENV_FILE` only when you want the main stack to load a different env file

# Run Server

- `docker compose up -d`
- connect to the OpenAI-compatible API at `http://llama.keng-pc.com:8080/v1`
  (Tailscale node `llama-server`, port `LLAMA_ARG_PORT`)
- install the launcher once with
  `ln -sf "$PWD/llama-cpp-toggle.desktop" ~/.local/share/applications/`, then
  start it from the Quickshell application launcher to start the server, switch
  between non-MTP and MTP, or stop it
- the launcher can also be called directly with `llama-toggle.sh non-mtp`, `llama-toggle.sh mtp`, or `llama-toggle.sh stop`

# Use with OpenCode

- the OpenCode config lives in the dotfiles `opencode` Stow package
  (`~/.config/opencode/opencode.jsonc`) and makes `llamacpp/qwen3.8-27b` the
  default and title model
- requests use the OpenAI-compatible chat API, and llama.cpp parses the model's
  tool calls itself
- `compatibility.reasoningField` sends `reasoning_content` back with earlier
  turns. The chat template keeps past reasoning, so each agent step only
  appends tokens and llama.cpp reuses the cached prefix
- in MTP mode select `llamacpp/qwen3.8-27b-mtp`, the same server model with
  the 80K limit, so OpenCode compacts before the smaller context fills
- reasoning variants are `low`, `medium`, `xhigh`, and `none`; the chat template
  rejects other effort names
- attach images with paths inside the project; the vision projector runs on the CPU
- web search uses OpenCode's built-in `websearch` tool with the keyless TinyFish
  provider, and `webfetch` reads pages
- run `opencode reload` after editing the config so the background service picks it up

# Run Benchmark

- stop the server first (`llama-toggle.sh stop`), then run `benchmark/run-bench.sh`
- each arm in `BENCHMARK_ARMS` (default `default mtp`) starts the image with the
  exact environment and command Compose would use; arm `name` layers `name.env`
  over `.env`
- `benchmark/agent-bench.py` replays OpenCode's real system prompt and tool
  schemas (`benchmark/fixtures/opencode-prefix.json`) and measures:
  - decode speed on short chat prompts, with MTP draft acceptance
  - cold prefill and decode speed at 8K, 32K, 64K, and 120K tokens of context
  - an agent session that appends 3K-token tool results up to 64K tokens, with
    per-step prefill time and cache hit ratio
  - cache behaviour after a title request, for a new session sharing the
    system prompt, when switching back to the first session, and after an early
    edit that forces a miss
  - process and total GPU VRAM per phase, and the minimum VRAM left free
- results go to `benchmark/summary.md`. Raw JSON and each arm's server
  environment are saved under `benchmark/results/`, where an optional
  `<arm>.note` file adds a description of that arm to the summary
- to compare arms from separate runs, call
  `benchmark/agent-bench.py --report benchmark/summary.md --results-dir benchmark/results <arm>...`
- useful overrides: `BENCHMARK_IMAGE` (compare another image tag),
  `BENCHMARK_SKIP_BUILD=1`, `BENCHMARK_RESULTS_DIR`, and `BENCHMARK_FLAGS`
  (for example `--scenarios decode,agent`)
- for kernel-level ubatch or depth sweeps, run `llama-bench` from the image, e.g.
  `docker run --rm --gpus all -v ./models:/models --entrypoint llama-bench llama-server -m /models/hf-home/hub/models--ISTA-DASLab--Qwen3.8-27B-GSQ-RCO-GGUF/snapshots/<rev>/Qwen3.8-27B-GSQ-RCO-IQ3_XXS-mtp.gguf -fa 1 -ctk q4_0 -ctv q4_0 -ub 256,512,1024 -d 0,32768`

# Notes

- downloaded models are cached under `./models/hf-home`
- with `LLAMA_ARG_OFFLINE=0` the first run downloads the model and vision projector into the shared Hugging Face cache
- runtime arguments live in `./.env` as `LLAMA_ARG_*` variables. llama.cpp
  ignores unknown names without a warning, so they must match exactly (for
  example `LLAMA_ARG_TEMPERATURE`, not `LLAMA_ARG_TEMP`)
- `llama-server` publishes no port of its own. It shares the Tailscale sidecar's
  network namespace, which serves the tailnet and `127.0.0.1:${LLAMA_ARG_PORT}` on the host
- the Tailscale sidecar sets `TS_ACCEPT_DNS=false`, so containers keep Docker's default DNS instead of adopting tailnet DNS settings
