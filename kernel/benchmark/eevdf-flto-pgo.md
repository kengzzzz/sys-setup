# Kernel benchmark summary

- Kernel: `6.18.32-1-eevdf-flto-pgo`
- Label: `eevdf-flto-pgo`
- Profile: `balanced`
- Baseline label: `cachyos-lts`
- Baseline profile: `balanced`
- Compared to: `cachyos-lts` on `6.18.32-1-cachyos-lts`

Positive change means this run is better than the baseline after applying each metric's better direction.

## Throughput

| Metric | Current median | Baseline median | Change vs baseline | Unit | Failed |
| --- | ---: | ---: | ---: | --- | ---: |
| dav1d decode | 0.5200 | 0.5300 | +1.89% better | seconds | 0 |
| x265 encode | 7.8600 | 7.8600 | +0.00% better | seconds | 0 |
| 7zip | 264101.00 | 264074.00 | +0.01% better | MIPS | 0 |
| sysbench cpu | 40654.62 | 40682.63 | -0.07% worse | events/sec | 0 |
| stress-ng matrix | 121011.98 | 121232.78 | -0.18% worse | bogo ops/sec | 0 |
| openssl sha256 | 2765733890.00 | 2765206320.00 | +0.02% better | bytes/sec | 0 |
| zstd compress | 0.0500 | 0.0500 | +0.00% better | seconds | 0 |

## Scheduler

| Metric | Current median | Baseline median | Change vs baseline | Unit | Failed |
| --- | ---: | ---: | ---: | --- | ---: |
| stress-ng switch | 22440668.64 | 19587865.43 | +14.56% better | bogo ops/sec | 0 |
| stress-ng futex | 4587745.15 | 4757025.69 | -3.56% worse | bogo ops/sec | 0 |
| schbench p99 | 21984.00 | 22048.00 | +0.29% better | usec | 0 |
| hackbench | 0.1830 | 0.2080 | +12.02% better | seconds | 0 |
| cyclictest max | 13.000 | 13.000 | +0.00% better | usec | 0 |

## Memory and filesystem

| Metric | Current median | Baseline median | Change vs baseline | Unit | Failed |
| --- | ---: | ---: | ---: | --- | ---: |
| stress-ng vm | 1403557.55 | 1400886.36 | +0.19% better | bogo ops/sec | 0 |
| fio randread | 23191.99 | 23147.59 | +0.19% better | IOPS | 0 |
| fio randwrite | 782802.95 | 763734.62 | +2.50% better | IOPS | 0 |
| fio seqread | 11788.61 | 9846.61 | +19.72% better | IOPS | 0 |
| fio seqwrite | 6673.82 | 6695.49 | -0.32% worse | IOPS | 0 |
