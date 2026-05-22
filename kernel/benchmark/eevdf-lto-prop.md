# Kernel benchmark summary

- Kernel: `6.18.32-1-eevdf-lto-prop`
- Label: `eevdf-lto-prop`
- Profile: `balanced`
- Baseline label: `cachyos-lts`
- Baseline profile: `balanced`
- Compared to: `cachyos-lts` on `6.18.32-1-cachyos-lts`

Positive change means this run is better than the baseline after applying each metric's better direction.

## Throughput

| Metric | Current median | Baseline median | Change vs baseline | Unit | Failed |
| --- | ---: | ---: | ---: | --- | ---: |
| dav1d decode | 0.5200 | 0.5300 | +1.89% better | seconds | 0 |
| x265 encode | 7.9400 | 7.8600 | -1.02% worse | seconds | 0 |
| 7zip | 263101.00 | 264074.00 | -0.37% worse | MIPS | 0 |
| sysbench cpu | 40297.17 | 40682.63 | -0.95% worse | events/sec | 0 |
| stress-ng matrix | 120952.37 | 121232.78 | -0.23% worse | bogo ops/sec | 0 |
| openssl sha256 | 2765799420.00 | 2765206320.00 | +0.02% better | bytes/sec | 0 |
| zstd compress | 0.0500 | 0.0500 | +0.00% better | seconds | 0 |

## Scheduler

| Metric | Current median | Baseline median | Change vs baseline | Unit | Failed |
| --- | ---: | ---: | ---: | --- | ---: |
| stress-ng switch | 22272167.90 | 19587865.43 | +13.70% better | bogo ops/sec | 0 |
| stress-ng futex | 4188210.79 | 4757025.69 | -11.96% worse | bogo ops/sec | 0 |
| schbench p99 | 22048.00 | 22048.00 | +0.00% better | usec | 0 |
| hackbench | 0.1970 | 0.2080 | +5.29% better | seconds | 0 |
| cyclictest max | 10.000 | 13.000 | +23.08% better | usec | 0 |

## Memory and filesystem

| Metric | Current median | Baseline median | Change vs baseline | Unit | Failed |
| --- | ---: | ---: | ---: | --- | ---: |
| stress-ng vm | 1402023.64 | 1400886.36 | +0.08% better | bogo ops/sec | 0 |
| fio randread | 23085.33 | 23147.59 | -0.27% worse | IOPS | 0 |
| fio randwrite | 758095.00 | 763734.62 | -0.74% worse | IOPS | 0 |
| fio seqread | 11700.09 | 9846.61 | +18.82% better | IOPS | 0 |
| fio seqwrite | 6403.05 | 6695.49 | -4.37% worse | IOPS | 0 |
