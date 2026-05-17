# llama.cpp benchmark summary

- Timestamp (UTC): `2026-05-17T01:26:09Z`
- Host: `x86_64`
- CPU threads: `32`
- GPU: `NVIDIA GeForce RTX 4070 Ti SUPER, 16376 MiB, 595.71.05`
- Baseline VRAM (used/peak): `13077` / `13087` MiB
- Candidate VRAM (used/peak): `13077` / `13087` MiB
- Model: `/models/hf-home/hub/models--unsloth--Qwen3.6-35B-A3B-GGUF/snapshots/a483e9e6cbd595906af30beda3187c2663a1118c/Qwen3.6-35B-A3B-UD-Q6_K_XL.gguf`
- Baseline image: `ghcr.io/ggml-org/llama.cpp@sha256:111681c55c83007572032ba96134f81b809b71a0a652cd70595298c6976d0276`
- Baseline image revision: `not labeled`
- Candidate image: `llama-server:latest`
- Candidate image revision: `b64739ea393b3c9d07cc9907e0a611f707838051`

## Benchmark setup

- Tool: `mtp-bench.py` (HTTP /completion)
- Number of prompts: `9`
- Predict tokens per request: `192`
- Temperature: `0.0`
- GPU layers: `999`
- Parallel slots: `1`
- Flash attention: `on`
- Context size: `131072`
- KV cache types: `q8_0 / q8_0`
- CPU MoE threads: `28`
- mmap: `off`

## Aggregate

| Metric | Baseline | Candidate | Delta |
| --- | ---: | ---: | ---: |
| Total predicted tokens | 1,419 | 1,419 | +0 |
| Total wall time (s) | 24.54 | 24.46 | -0.33% |
| Aggregate throughput | 57.82 tok/s | 58.01 tok/s | +0.33% |

## Per-prompt results

| Prompt | Baseline tok/s | Candidate tok/s | Delta |
| --- | ---: | ---: | ---: |
| `code_python` | 64.60 tok/s | 64.86 tok/s | +0.40% |
| `code_cpp` | 64.73 tok/s | 65.07 tok/s | +0.52% |
| `explain_concept` | 64.95 tok/s | 65.13 tok/s | +0.28% |
| `summarize` | 64.98 tok/s | 65.47 tok/s | +0.75% |
| `qa_factual` | 65.22 tok/s | 65.39 tok/s | +0.26% |
| `translation` | 66.42 tok/s | 67.28 tok/s | +1.30% |
| `creative_short` | 65.02 tok/s | 65.15 tok/s | +0.21% |
| `stepwise_math` | 64.95 tok/s | 64.91 tok/s | -0.06% |
| `long_code_review` | 64.51 tok/s | 64.67 tok/s | +0.25% |

## Notes

- This benchmark measures real HTTP `/completion` latency including network round-trip within the host.
- The benchmark reuses the repo env file as the single source of truth for `LLAMA_ARG_*` runtime settings.
- The candidate image is compared against the official llama.cpp image as the baseline.
- `n_predict=192`, `temperature=0.0`, `seed=42`, `cache_prompt=false` across all requests.
- Raw artifacts: `results/baseline.json`, `results/candidate.json`, and both `docker inspect` outputs.
