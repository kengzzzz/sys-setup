# Non-MTP vs MTP benchmark

- Timestamp (UTC): `2026-09-19T07:47:10Z`
- Host: `x86_64`
- CPU threads: `32`
- GPU: `NVIDIA GeForce RTX 5080, 16303 MiB, 615.71.09`
- Model: `/models/hf-home/hub/models--unsloth--Qwen3.8-27B-GGUF/snapshots/4ca720788d1e01f1bff70c033e0d0028fd02e502/Qwen3.8-27B-UD-Q2_K_XL.gguf`
- Image: `llama-server:latest`
- Image revision: `b23701f77d47dad9de834d59ebfcbe25c9e8b46f`

## Configuration

- Both arms use the same image, model, prompts, and runtime settings.
- Non-MTP removes every `LLAMA_ARG_SPEC_*` environment variable.
- MTP settings: `LLAMA_ARG_SPEC_DRAFT_BACKEND_SAMPLING=on`, `LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_K=q4_0`, `LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_V=q4_0`, `LLAMA_ARG_SPEC_DRAFT_N_MAX=2`, `LLAMA_ARG_SPEC_TYPE=draft-mtp`
- Repetitions per prompt: `3`
- Predict tokens per request: `192`
- Temperature: `0.0`; seed: `42`; prompt cache: disabled.

## Aggregate comparison

| Metric | Non-MTP | MTP | Delta |
| --- | ---: | ---: | ---: |
| End-to-end throughput | 67.74 tok/s | 105.10 tok/s | +55.14% |
| Server decode throughput | 72.27 tok/s | 117.29 tok/s | +62.30% |
| Total wall time | 70.28 s | 45.30 s | -35.54% |
| Idle process VRAM | 11,534 MiB | 12,512 MiB | +978 MiB |
| Peak process VRAM | 11,746 MiB | 12,742 MiB | +996 MiB |
| MTP draft acceptance | n/a | 0.732 | n/a |

## Per-prompt server throughput

| Prompt | Non-MTP | MTP | Delta | MTP accept rate |
| --- | ---: | ---: | ---: | ---: |
| `code_python` | 71.84 tok/s | 120.60 tok/s | +67.87% | 0.773 |
| `code_cpp` | 71.79 tok/s | 122.80 tok/s | +71.05% | 0.796 |
| `explain_concept` | 71.94 tok/s | 109.75 tok/s | +52.57% | 0.658 |
| `summarize` | 71.75 tok/s | 118.27 tok/s | +64.85% | 0.750 |
| `qa_factual` | 71.95 tok/s | 126.26 tok/s | +75.48% | 0.832 |
| `translation` | 71.90 tok/s | 124.30 tok/s | +72.89% | 0.808 |
| `creative_short` | 71.96 tok/s | 101.08 tok/s | +40.47% | 0.564 |
| `stepwise_math` | 71.93 tok/s | 133.45 tok/s | +85.53% | 0.911 |
| `long_code_review` | 71.56 tok/s | 102.78 tok/s | +43.62% | 0.592 |

## Notes

- End-to-end throughput includes local HTTP round-trip time; server decode throughput uses llama.cpp timing data.
- VRAM is sampled from the llama-server process during model load and inference, not from total GPU usage.
- The two arms run sequentially: non-MTP first, then MTP.
- Raw artifacts are under `benchmark/results/`.
