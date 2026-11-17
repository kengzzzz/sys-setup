# Kernel benchmark

Run these in `kernel/benchmark`. Boot the CachyOS LTS kernel for the baseline:

```sh
BENCH_LABEL=cachyos-lts docker compose run --rm benchmark
```

Then boot the kernel under test:

```sh
BENCH_LABEL=eevdf-lto-prop BENCH_BASELINE_LABEL=cachyos-lts docker compose run --rm benchmark
```

Reports go to `results/`, the newest also to `results/latest.md`. `BENCH_PROFILE` is
`smoke`, `balanced` (default) or `full`.

## Game frame rates

Use CS2 on a Workshop "FPS Benchmark" map with vsync off, `fps_max 0` and
`-condebug`. Per launch, do one warm-up run and three measured runs, then quit.

```sh
scripts/cs2-collect.sh bore   # moves console.log to results/games/bore/
python3 scripts/game-report.py results/games/bore results/games/lavd
```

The first directory is the baseline. Alternate the configs as A B C, then C B A. A
change counts only when the run ranges do not overlap.
