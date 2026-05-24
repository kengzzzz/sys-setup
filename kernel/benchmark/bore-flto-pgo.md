# Kernel benchmark summary

- Kernel: `7.0.10-1-bore-flto-pgo`
- Label: `bore-flto-pgo`
- Profile: `full`
- Baseline label: `cachyos-lts`
- Baseline profile: `full`
- Compared to: `cachyos-lts` on `6.18.32-1-cachyos-lts`

Positive change means this run is better than the baseline after applying each metric's better direction.

## Throughput

| Metric | Current median | Baseline median | Change vs baseline | Unit | Failed |
| --- | ---: | ---: | ---: | --- | ---: |
| dav1d decode | 0.5000 | 0.5300 | +5.66% better | seconds | 0 |
| x265 encode | 7.4900 | 7.9700 | +6.02% better | seconds | 0 |
| 7zip | 268929.00 | 261415.00 | +2.87% better | MIPS | 0 |
| sysbench cpu | 41102.53 | 40218.57 | +2.20% better | events/sec | 0 |
| stress-ng matrix | 121983.68 | 119931.61 | +1.71% better | bogo ops/sec | 0 |
| openssl sha256 | 2765478300.00 | 2761244670.00 | +0.15% better | bytes/sec | 0 |
| zstd compress | 0.0400 | 0.0500 | +20.00% better | seconds | 0 |

## Scheduler

| Metric | Current median | Baseline median | Change vs baseline | Unit | Failed |
| --- | ---: | ---: | ---: | --- | ---: |
| stress-ng switch | 21057843.39 | 19528911.88 | +7.83% better | bogo ops/sec | 0 |
| stress-ng futex | 5635108.01 | 4837731.66 | +16.48% better | bogo ops/sec | 0 |
| schbench p99 | 32352.00 | 22112.00 | -46.31% worse | usec | 0 |
| hackbench | 0.2110 | 0.2120 | +0.47% better | seconds | 0 |
| cyclictest max | 10.000 | 11.000 | +9.09% better | usec | 0 |

## Memory and filesystem

| Metric | Current median | Baseline median | Change vs baseline | Unit | Failed |
| --- | ---: | ---: | ---: | --- | ---: |
| stress-ng vm | 1432510.16 | 1406163.11 | +1.87% better | bogo ops/sec | 0 |
| fio randread | 22172.13 | 22265.92 | -0.42% worse | IOPS | 0 |
| fio randwrite | 754230.93 | 753819.74 | +0.05% better | IOPS | 0 |
| fio seqread | 11169.73 | 10128.50 | +10.28% better | IOPS | 0 |
| fio seqwrite | 7228.35 | 6671.10 | +8.35% better | IOPS | 0 |
