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
