# Non-MTP vs MTP benchmark

- Timestamp (UTC): `2026-09-19T00:11:40Z`
- Host: `x86_64`
- CPU threads: `32`
- GPU: `NVIDIA GeForce RTX 5080, 16303 MiB, 615.71.09`
- Model: `/models/hf-home/hub/models--decent-jawfish--bonsai-2-27b-mtp/snapshots/5edf5f552d45e40b81f0255a8bb443af35850722/Bonsai-2-27B-PQ2_0-MTP.gguf`
- Image: `llama-server:latest`
- Image revision: `9a9394a895b96003ca842a6041cb28ac49a108f7`

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
| End-to-end throughput | 89.58 tok/s | 117.45 tok/s | +31.11% |
| Server decode throughput | 96.96 tok/s | 131.60 tok/s | +35.74% |
| Total wall time | 44.71 s | 34.10 s | -23.73% |
| Idle process VRAM | 11,984 MiB | 13,306 MiB | +1,322 MiB |
| Peak process VRAM | 11,996 MiB | 13,328 MiB | +1,332 MiB |
| MTP draft acceptance | n/a | 0.669 | n/a |

## Per-prompt server throughput

| Prompt | Non-MTP | MTP | Delta | MTP accept rate |
| --- | ---: | ---: | ---: | ---: |
| `code_python` | 96.22 tok/s | 132.24 tok/s | +37.44% | 0.683 |
| `code_cpp` | 95.78 tok/s | 123.99 tok/s | +29.46% | 0.611 |
| `explain_concept` | 96.25 tok/s | 123.10 tok/s | +27.90% | 0.605 |
| `summarize` | 96.48 tok/s | 129.74 tok/s | +34.47% | 0.654 |
| `qa_factual` | 0.00 tok/s | 0.00 tok/s | +0.00% | n/a |
| `translation` | 96.52 tok/s | 142.29 tok/s | +47.42% | 0.778 |
| `creative_short` | 96.38 tok/s | 126.45 tok/s | +31.20% | 0.627 |
| `stepwise_math` | 96.52 tok/s | 139.69 tok/s | +44.73% | 0.750 |
| `long_code_review` | 0.00 tok/s | 0.00 tok/s | +0.00% | n/a |

## Notes

- End-to-end throughput includes local HTTP round-trip time; server decode throughput uses llama.cpp timing data.
- VRAM is sampled from the llama-server process during model load and inference, not from total GPU usage.
- The two arms run sequentially: non-MTP first, then MTP.
- Raw artifacts are under `benchmark/results/`.
