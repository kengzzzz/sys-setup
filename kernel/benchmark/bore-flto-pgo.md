# Kernel benchmark summary

- Kernel: `7.0.9-1-bore-flto-pgo`
- Label: `bore-flto-pgo`
- Profile: `balanced`
- Baseline label: `cachyos-lts`
- Baseline profile: `balanced`
- Compared to: `cachyos-lts` on `6.18.32-1-cachyos-lts`

Positive change means this run is better than the baseline after applying each metric's better direction.

## Throughput

| Metric | Current median | Baseline median | Change vs baseline | Unit | Failed |
| --- | ---: | ---: | ---: | --- | ---: |
| dav1d decode | 0.5000 | 0.5300 | +5.66% better | seconds | 0 |
| x265 encode | 7.5200 | 7.8600 | +4.33% better | seconds | 0 |
| 7zip | 266521.00 | 264074.00 | +0.93% better | MIPS | 0 |
| sysbench cpu | 40788.59 | 40682.63 | +0.26% better | events/sec | 0 |
| stress-ng matrix | 121269.70 | 121232.78 | +0.03% better | bogo ops/sec | 0 |
| openssl sha256 | 2766752970.00 | 2765206320.00 | +0.06% better | bytes/sec | 0 |
| zstd compress | 0.0400 | 0.0500 | +20.00% better | seconds | 0 |

## Scheduler

| Metric | Current median | Baseline median | Change vs baseline | Unit | Failed |
| --- | ---: | ---: | ---: | --- | ---: |
| stress-ng switch | 20527756.45 | 19587865.43 | +4.80% better | bogo ops/sec | 0 |
| stress-ng futex | 5146673.31 | 4757025.69 | +8.19% better | bogo ops/sec | 0 |
| schbench p99 | 33344.00 | 22048.00 | -51.23% worse | usec | 0 |
| hackbench | 0.2180 | 0.2080 | -4.81% worse | seconds | 0 |
| cyclictest max | 10.000 | 13.000 | +23.08% better | usec | 0 |

## Memory and filesystem

| Metric | Current median | Baseline median | Change vs baseline | Unit | Failed |
| --- | ---: | ---: | ---: | --- | ---: |
| stress-ng vm | 1394611.41 | 1400886.36 | -0.45% worse | bogo ops/sec | 0 |
| fio randread | 22937.94 | 23147.59 | -0.91% worse | IOPS | 0 |
| fio randwrite | 738193.85 | 763734.62 | -3.34% worse | IOPS | 0 |
| fio seqread | 7443.44 | 9846.61 | -24.41% worse | IOPS | 0 |
| fio seqwrite | 7183.32 | 6695.49 | +7.29% better | IOPS | 0 |
