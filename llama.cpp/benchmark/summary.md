# Coding-agent benchmark

- Timestamp (UTC): `2026-10-25T13:39:19Z`
- GPU: `NVIDIA GeForce RTX 5080, 16303 MiB, 615.78.08`
- Image revision: `1a0b56cec73dac938e0602c974b21dc8e2862830`
- Workload prefix: OpenCode system prompt + tool schemas (`benchmark/fixtures/opencode-prefix.json`)
- Agent session: 3000-token tool results appended until ~65536 tokens
- Decode: 2 x 9 short chat prompts, 192 tokens, temperature 0

## Arms

- `baseline-default`: the old stack, a llama.cpp 339f324 image with the Codex patches running JonathanColetti IQ2_M with q8_0 K/V, 100K context, ubatch 64, default slot similarity and MTP off
- `baseline-mtp`: old stack with MTP on, which was the previous default
- `oldimage-default`: old image 339f324 with the new model, `.env` and Compose command, to isolate the effect of the llama.cpp update
- `default`: new image 1a0b56c with `.env`, the shipped default
- `mtp`: new image with `.env` + `mtp.env` (MTP on, 80K context)

## Settings

| Metric | `baseline-default` | `baseline-mtp` | `oldimage-default` | `default` | `mtp` |
| --- | ---: | ---: | ---: | ---: | ---: |
| model file | `Qwen3.8-27B-Uncensored-IQ2_M.gguf` | `Qwen3.8-27B-Uncensored-IQ2_M.gguf` | `Qwen3.8-27B-GSQ-RCO-IQ3_XXS-mtp.gguf` | `Qwen3.8-27B-GSQ-RCO-IQ3_XXS-mtp.gguf` | `Qwen3.8-27B-GSQ-RCO-IQ3_XXS-mtp.gguf` |
| `LLAMA_ARG_CTX_SIZE` | `102400` | `102400` | `131072` | `131072` | `81920` |
| `LLAMA_ARG_UBATCH` | `64` | `64` | `512` | `512` | `512` |
| `LLAMA_ARG_N_PARALLEL` | `1` | `1` | `1` | `1` | `1` |
| `LLAMA_ARG_CACHE_TYPE_K` | `q8_0` | `q8_0` | `q4_0` | `q4_0` | `q4_0` |
| `LLAMA_ARG_CACHE_TYPE_V` | `q8_0` | `q8_0` | `q4_0` | `q4_0` | `q4_0` |
| `LLAMA_ARG_CACHE_RAM` | `-` | `-` | `16384` | `16384` | `16384` |
| `LLAMA_ARG_SPEC_TYPE` | `-` | `draft-mtp` | `-` | `-` | `draft-mtp` |
| `command` | `` | `` | `--slot-prompt-similarity 0.5` | `--slot-prompt-similarity 0.5` | `--slot-prompt-similarity 0.5` |

## Results

| Metric | `baseline-default` | `baseline-mtp` | `oldimage-default` | `default` | `mtp` |
| --- | ---: | ---: | ---: | ---: | ---: |
| Decode, short prompts (tok/s) | 62.81 | 98.79 | 60.16 | 60.25 | 97.92 |
| MTP draft acceptance | - | 0.669 | - | - | 0.701 |
| Prefill 8K cold (tok/s) | 1227 | 1175 | 1828 | 1808 | 1734 |
| Prefill 32K cold (tok/s) | 1128 | 1085 | 1661 | 1654 | 1579 |
| Prefill 64K cold (tok/s) | 998 | 957 | 1427 | 1430 | 1354 |
| Prefill 120K cold (tok/s) | - | - | 1148 | 1156 | - |
| Time to first token 8K cold (s) | 6.84 | 7.14 | 4.59 | 4.64 | 4.84 |
| Time to first token 32K cold (s) | 28.39 | 29.51 | 19.28 | 19.36 | 20.28 |
| Time to first token 64K cold (s) | 67.08 | 69.90 | 46.90 | 46.79 | 49.40 |
| Time to first token 120K cold (s) | - | - | 110.88 | 110.14 | - |
| Decode at 8K depth (tok/s) | 59.52 | 112.91 | 55.65 | 56.06 | 101.30 |
| Decode at 32K depth (tok/s) | 52.04 | 86.28 | 48.84 | 48.98 | 88.18 |
| Decode at 64K depth (tok/s) | 44.39 | 73.09 | 41.80 | 42.22 | 66.76 |
| Decode at 120K depth (tok/s) | - | - | 32.94 | 32.95 | - |
| Agent loop: steps | 16 | 16 | 16 | 16 | 16 |
| Agent loop: cache hit ratio | 0.909 | 0.909 | 0.909 | 0.909 | 0.909 |
| Agent loop: mean new tokens per step | 3298 | 3298 | 3298 | 3298 | 3298 |
| Agent loop: mean prefill per step (s) | 3.40 | 3.56 | 2.41 | 2.42 | 2.53 |
| Agent loop: max prefill per step (s) | 5.22 | 5.50 | 3.70 | 3.72 | 3.90 |
| Resume after title request: tokens re-processed | 717 | 717 | 717 | 717 | 717 |
| Resume after title request: prefill (s) | 0.94 | 1.00 | 0.71 | 0.70 | 0.73 |
| New session, shared prefix: tokens processed | 60 | 60 | 508 | 508 | 508 |
| Switch back to first session: tokens re-processed | 53959 | 53959 | 25 | 25 | 25 |
| Switch back to first session: prefill (s) | 54.83 | 57.24 | 0.16 | 0.16 | 0.18 |
| Early-history edit (miss): tokens re-processed | 53962 | 53962 | 54448 | 54448 | 54448 |
| Early-history edit (miss): prefill (s) | 54.94 | 57.26 | 38.73 | 38.85 | 40.72 |
| Idle process VRAM (MiB) | 13,286 | 14,552 | 12,724 | 12,722 | 12,822 |
| Peak process VRAM (MiB) | 13,306 | 14,590 | 13,024 | 13,022 | 13,138 |
| Peak GPU used incl. desktop (MiB) | 14,046 | 15,299 | 13,742 | 13,806 | 13,841 |
| Min free VRAM during run (MiB) | 2,257 | 1,004 | 2,561 | 2,497 | 2,462 |

## Decode per prompt (tok/s)

| Prompt | `baseline-default` | `baseline-mtp` | `oldimage-default` | `default` | `mtp` |
| --- | ---: | ---: | ---: | ---: | ---: |
| `code_python` | 62.45 | 101.15 | 60.25 | 59.90 | 98.59 |
| `code_cpp` | 62.48 | 99.28 | 60.05 | 59.91 | 91.97 |
| `explain_concept` | 62.51 | 87.51 | 59.33 | 59.97 | 88.97 |
| `summarize` | 62.38 | 109.52 | 59.39 | 59.95 | 106.84 |
| `qa_factual` | 62.56 | 105.97 | 59.73 | 59.94 | 105.61 |
| `translation` | 62.44 | 95.90 | 59.75 | 60.08 | 94.22 |
| `creative_short` | 62.28 | 81.78 | 59.36 | 60.25 | 88.26 |
| `stepwise_math` | 62.45 | 100.41 | 60.16 | 59.81 | 97.39 |
| `refactor` | 62.42 | 97.86 | 59.95 | 59.48 | 106.88 |

## Notes

- Prefill rows force a cache miss by changing the first tool description; decode at depth is measured on the same request.
- Agent rows come from llama.cpp `timings`. Tokens re-processed is `prompt_n`; everything else was reused from the slot, a context checkpoint, or the host prompt cache.
- VRAM is sampled every 0.25 s. GPU used includes the desktop, so free VRAM is what other applications have left.
- Raw results and each arm's exact server environment are in `benchmark/results/`.
