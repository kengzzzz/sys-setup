# llama.cpp server

## Build

The host needs the NVIDIA driver and `nvidia-container-toolkit`. Check GPU containers:

```sh
docker run --rm --gpus all nvidia/cuda:13.4.3-base-ubuntu24.04 nvidia-smi
docker compose build llama-server
```

If CUDA fails in Docker after a GPU or driver change, run
`sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml`.

The build pins the llama.cpp commit and CUDA image, and targets only `sm_120a`, the
RTX 50 series.

## Configure

Copy `.env.example` to `.env` and edit it.

- The model is `Qwen3.8-27B-GSQ-RCO-IQ3_XXS-mtp.gguf` from
  `ISTA-DASLab/Qwen3.8-27B-GSQ-RCO-GGUF`. llama.cpp loads its MTP head only in MTP
  mode.
- `LLAMA_ARG_OFFLINE=1` serves the cached model without checking the repo. Set it to
  `0` for the first download or a model change.
- Defaults: 128K context, Q4_0 K/V cache, MTP off. MTP mode loads `mtp.env` on top
  and uses 80K context.
- `--slot-prompt-similarity` is set in the Compose `command`, since it has no env
  variable.
- `TS_AUTHKEY` is the Tailscale auth key for the sidecar. `HF_TOKEN` is only for a
  gated model repo.
- llama.cpp ignores misspelled `LLAMA_ARG_*` names without a warning. Use
  `LLAMA_ARG_TEMPERATURE`, not `LLAMA_ARG_TEMP`.

## Run

```sh
docker compose up -d
```

The API is at `http://llama.keng-pc.com:8080/v1` on the Tailscale node
`llama-server`, and at `127.0.0.1:${LLAMA_ARG_PORT}` on the host.

`llama-toggle.sh non-mtp`, `mtp` or `stop` switches the server. To do that from the
app launcher, link the desktop entry once:

```sh
ln -sf "$PWD/llama-cpp-toggle.desktop" ~/.local/share/applications/
```

## OpenCode

The config is in the dotfiles `opencode` Stow package. It uses
`llamacpp/qwen3.8-27b`, or `llamacpp/qwen3.8-27b-mtp` in MTP mode, which compacts at
the 80K limit. The reasoning variants are `low`, `medium`, `xhigh` and `none`. Run
`opencode reload` after you edit the config.

## Benchmark

Stop the server, then run `benchmark/run-bench.sh`. It runs each arm in
`BENCHMARK_ARMS` (default `default mtp`) through `benchmark/agent-bench.py`, which
replays OpenCode's prompt and tools. It measures decode speed, prefill at up to 120K
tokens, cache hits in an agent session and VRAM use.

Results go to `benchmark/summary.md` and `benchmark/results/`. To compare arms from
separate runs:

```sh
benchmark/agent-bench.py --report benchmark/summary.md --results-dir benchmark/results <arm>...
```
