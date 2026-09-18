# Non-MTP vs MTP benchmark

- Timestamp (UTC): `2026-09-17T08:09:18Z`
- Host: `x86_64`
- CPU threads: `32`
- GPU: `NVIDIA GeForce RTX 5080, 16303 MiB, 615.71.09`
- Model: `/models/hf-home/hub/models--unsloth--Qwen3.8-27B-GGUF/snapshots/4ca720788d1e01f1bff70c033e0d0028fd02e502/Qwen3.8-27B-UD-Q2_K_XL.gguf`
- Image: `llama-server:latest`
- Image revision: `35822afe58475e0506cd51e6573903e46d4c67c9`

## Configuration

- Both arms use the same image, model, prompts, and runtime settings.
- Non-MTP removes every `LLAMA_ARG_SPEC_*` environment variable.
- MTP settings: `LLAMA_ARG_SPEC_DRAFT_BACKEND_SAMPLING=on`, `LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_K=q4_0`, `LLAMA_ARG_SPEC_DRAFT_CACHE_TYPE_V=q4_0`, `LLAMA_ARG_SPEC_TYPE=draft-mtp`
- Repetitions per prompt: `3`
- Predict tokens per request: `192`
- Temperature: `0.0`; seed: `42`; prompt cache: disabled.

## Aggregate comparison

| Metric | Non-MTP | MTP | Delta |
| --- | ---: | ---: | ---: |
| End-to-end throughput | 65.46 tok/s | 103.32 tok/s | +57.83% |
| Server decode throughput | 69.77 tok/s | 115.24 tok/s | +65.19% |
| Total wall time | 72.73 s | 46.08 s | -36.64% |
| Idle process VRAM | 12,144 MiB | 13,356 MiB | +1,212 MiB |
| Peak process VRAM | 12,356 MiB | 13,586 MiB | +1,230 MiB |
| MTP draft acceptance | n/a | 0.632 | n/a |

## Per-prompt server throughput

| Prompt | Non-MTP | MTP | Delta | MTP accept rate |
| --- | ---: | ---: | ---: | ---: |
| `code_python` | 69.08 tok/s | 118.44 tok/s | +71.45% | 0.665 |
| `code_cpp` | 69.10 tok/s | 119.05 tok/s | +72.28% | 0.672 |
| `explain_concept` | 69.37 tok/s | 100.64 tok/s | +45.08% | 0.513 |
| `summarize` | 69.29 tok/s | 116.14 tok/s | +67.62% | 0.647 |
| `qa_factual` | 69.57 tok/s | 127.35 tok/s | +83.05% | 0.736 |
| `translation` | 69.60 tok/s | 126.80 tok/s | +82.19% | 0.736 |
| `creative_short` | 69.57 tok/s | 96.54 tok/s | +38.76% | 0.475 |
| `stepwise_math` | 69.51 tok/s | 138.06 tok/s | +98.61% | 0.834 |
| `long_code_review` | 69.20 tok/s | 102.86 tok/s | +48.65% | 0.538 |

## Notes

- End-to-end throughput includes local HTTP round-trip time; server decode throughput uses llama.cpp timing data.
- VRAM is sampled from the llama-server process during model load and inference, not from total GPU usage.
- The two arms run sequentially: non-MTP first, then MTP.
- Raw artifacts are under `benchmark/results/`.
