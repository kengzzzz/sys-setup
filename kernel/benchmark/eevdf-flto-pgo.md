# Kernel benchmark summary

- Kernel: `7.0.9-1-eevdf-flto-pgo`
- Label: `eevdf-flto-pgo`
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
| 7zip | 264196.00 | 261415.00 | +1.06% better | MIPS | 0 |
| sysbench cpu | 40267.40 | 40218.57 | +0.12% better | events/sec | 0 |
| stress-ng matrix | 120265.37 | 119931.61 | +0.28% better | bogo ops/sec | 0 |
| openssl sha256 | 2763833340.00 | 2761244670.00 | +0.09% better | bytes/sec | 0 |
| zstd compress | 0.0500 | 0.0500 | +0.00% better | seconds | 0 |

## Scheduler

| Metric | Current median | Baseline median | Change vs baseline | Unit | Failed |
| --- | ---: | ---: | ---: | --- | ---: |
| stress-ng switch | 20148801.90 | 19528911.88 | +3.17% better | bogo ops/sec | 0 |
| stress-ng futex | 4374187.42 | 4837731.66 | -9.58% worse | bogo ops/sec | 0 |
| schbench p99 | 22304.00 | 22112.00 | -0.87% worse | usec | 0 |
| hackbench | 0.2120 | 0.2120 | +0.00% better | seconds | 0 |
| cyclictest max | 11.000 | 11.000 | +0.00% better | usec | 0 |

## Memory and filesystem

| Metric | Current median | Baseline median | Change vs baseline | Unit | Failed |
| --- | ---: | ---: | ---: | --- | ---: |
| stress-ng vm | 1416295.26 | 1406163.11 | +0.72% better | bogo ops/sec | 0 |
| fio randread | 22166.73 | 22265.92 | -0.45% worse | IOPS | 0 |
| fio randwrite | 755470.83 | 753819.74 | +0.22% better | IOPS | 0 |
| fio seqread | 11171.39 | 10128.50 | +10.30% better | IOPS | 0 |
| fio seqwrite | 7189.89 | 6671.10 | +7.78% better | IOPS | 0 |
