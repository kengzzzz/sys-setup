# Kernel benchmark summary

- Kernel: `7.0.9-1-bore-flto-pgo`
- Label: `bore-flto-pgo`
- Profile: `full`
- Baseline label: `cachyos-lts`
- Baseline profile: `full`
- Compared to: `cachyos-lts` on `6.18.32-1-cachyos-lts`

Positive change means this run is better than the baseline after applying each metric's better direction.

## Throughput

| Metric | Current median | Baseline median | Change vs baseline | Unit | Failed |
| --- | ---: | ---: | ---: | --- | ---: |
| dav1d decode | 0.5100 | 0.5300 | +3.77% better | seconds | 0 |
| x265 encode | 7.6100 | 7.9700 | +4.52% better | seconds | 0 |
| 7zip | 263269.00 | 261415.00 | +0.71% better | MIPS | 0 |
| sysbench cpu | 40270.88 | 40218.57 | +0.13% better | events/sec | 0 |
| stress-ng matrix | 119845.60 | 119931.61 | -0.07% worse | bogo ops/sec | 0 |
| openssl sha256 | 2765756830.00 | 2761244670.00 | +0.16% better | bytes/sec | 0 |
| zstd compress | 0.0500 | 0.0500 | +0.00% better | seconds | 0 |

## Scheduler

| Metric | Current median | Baseline median | Change vs baseline | Unit | Failed |
| --- | ---: | ---: | ---: | --- | ---: |
| stress-ng switch | 20179628.24 | 19528911.88 | +3.33% better | bogo ops/sec | 0 |
| stress-ng futex | 6090782.86 | 4837731.66 | +25.90% better | bogo ops/sec | 0 |
| schbench p99 | 32672.00 | 22112.00 | -47.76% worse | usec | 0 |
| hackbench | 0.2180 | 0.2120 | -2.83% worse | seconds | 0 |
| cyclictest max | 11.000 | 11.000 | +0.00% better | usec | 0 |

## Memory and filesystem

| Metric | Current median | Baseline median | Change vs baseline | Unit | Failed |
| --- | ---: | ---: | ---: | --- | ---: |
| stress-ng vm | 1423034.01 | 1406163.11 | +1.20% better | bogo ops/sec | 0 |
| fio randread | 22171.69 | 22265.92 | -0.42% worse | IOPS | 0 |
| fio randwrite | 742928.24 | 753819.74 | -1.44% worse | IOPS | 0 |
| fio seqread | 5442.79 | 10128.50 | -46.26% worse | IOPS | 0 |
| fio seqwrite | 7283.86 | 6671.10 | +9.19% better | IOPS | 0 |
