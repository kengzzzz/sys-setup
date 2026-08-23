# Non-MTP vs MTP benchmark

- Timestamp (UTC): `2026-08-22T08:46:41Z`
- Host: `x86_64`
- CPU threads: `32`
- GPU: `NVIDIA GeForce RTX 4070 Ti SUPER, 16376 MiB, 610.57.04`
- Model: `/models/hf-home/hub/models--unsloth--Qwen3.8-27B-GGUF/snapshots/4ca720788d1e01f1bff70c033e0d0028fd02e502/Qwen3.8-27B-UD-Q2_K_XL.gguf`
- Image: `llama-server:latest`
- Image revision: `d775b8967a46d8beb110d444aa3b8938179e0dd8`

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
| End-to-end throughput | 49.75 tok/s | 80.07 tok/s | +60.95% |
| Server decode throughput | 52.12 tok/s | 86.86 tok/s | +66.67% |
| Total wall time | 95.70 s | 59.46 s | -37.87% |
| Idle process VRAM | 13,924 MiB | 15,396 MiB | +1,472 MiB |
| Peak process VRAM | 14,050 MiB | 15,532 MiB | +1,482 MiB |
| MTP draft acceptance | n/a | 0.648 | n/a |

## Per-prompt server throughput

| Prompt | Non-MTP | MTP | Delta | MTP accept rate |
| --- | ---: | ---: | ---: | ---: |
| `code_python` | 52.19 tok/s | 89.65 tok/s | +71.78% | 0.681 |
| `code_cpp` | 51.88 tok/s | 97.98 tok/s | +88.87% | 0.776 |
| `explain_concept` | 51.93 tok/s | 75.33 tok/s | +45.07% | 0.519 |
| `summarize` | 51.83 tok/s | 86.47 tok/s | +66.86% | 0.647 |
| `qa_factual` | 51.92 tok/s | 91.13 tok/s | +75.51% | 0.705 |
| `translation` | 51.86 tok/s | 91.43 tok/s | +76.30% | 0.703 |
| `creative_short` | 51.76 tok/s | 76.08 tok/s | +46.98% | 0.529 |
| `stepwise_math` | 51.73 tok/s | 102.77 tok/s | +98.67% | 0.840 |
| `long_code_review` | 51.29 tok/s | 75.71 tok/s | +47.60% | 0.534 |

## Notes

- End-to-end throughput includes local HTTP round-trip time; server decode throughput uses llama.cpp timing data.
- VRAM is sampled from the llama-server process during model load and inference, not from total GPU usage.
- The two arms run sequentially: non-MTP first, then MTP.
- Raw artifacts are under `benchmark/results/`.
