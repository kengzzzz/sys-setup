# Kernel Benchmark

Run this benchmark from `kernel/benchmark`.

## Baseline

Reboot into the CachyOS LTS kernel, then run:

```sh
BENCH_LABEL=cachyos-lts docker compose run --rm benchmark
```

## Compare a Kernel

Reboot into the kernel being tested, then run:

```sh
BENCH_LABEL=eevdf-lto-prop BENCH_BASELINE_LABEL=cachyos-lts docker compose run --rm benchmark
```

Reports are written to `results/`. The latest report is copied to `results/latest.md`.
By default, reports compare against the newest `BENCH_BASELINE_LABEL` run with the
same profile as the current run.

## Profiles

- `BENCH_PROFILE=smoke BENCH_RUNS=1` for a short wiring check.
- `BENCH_PROFILE=balanced` for the default comparison suite.
- `BENCH_PROFILE=full` for longer stress and filesystem runs.

The CSV format is:

```text
timestamp,kernel,label,profile,group,metric,unit,direction,run,value,status
```

## Game Frame Rates

For scheduler comparisons, use CS2 with a Workshop "FPS Benchmark" map: vsync off,
`fps_max 0`, launch option `-condebug`. Per launch, do one warm-up run plus three
runs, quit, then file `game/csgo/console.log` under the config name. Optional
MangoHud CSVs (`no_display`, warm-up not logged) go in the same directory; add
MangoHud only if it doesn't shift the in-game numbers beyond the noise.

```sh
scripts/cs2-collect.sh bore   # moves the log to results/games/bore/
python3 scripts/game-report.py results/games/bore results/games/lavd results/games/bpfland
```

The first directory is the baseline (`--baseline`). Each console log's first
result is dropped (`--warmup`), and MangoHud logs lose 2 s per end (`--trim`).
Alternate configs (A B C, C B A) and run one config five times first to learn
the noise; a change is only "clear" when the run ranges don't overlap.
