# Kernel benchmark summary

- Kernel: `6.18.32-1-cachyos-lts`
- Label: `cachyos-lts`
- Profile: `full`
- Baseline label: `cachyos-lts`
- Baseline profile: `full`
- This run is the baseline.

Positive change means this run is better than the baseline after applying each metric's better direction.

## Throughput

| Metric | Current median | Baseline median | Change vs baseline | Unit | Failed |
| --- | ---: | ---: | ---: | --- | ---: |
| dav1d decode | 0.5300 | n/a | n/a | seconds | 0 |
| x265 encode | 7.9700 | n/a | n/a | seconds | 0 |
| 7zip | 261415.00 | n/a | n/a | MIPS | 0 |
| sysbench cpu | 40218.57 | n/a | n/a | events/sec | 0 |
| stress-ng matrix | 119931.61 | n/a | n/a | bogo ops/sec | 0 |
| openssl sha256 | 2761244670.00 | n/a | n/a | bytes/sec | 0 |
| zstd compress | 0.0500 | n/a | n/a | seconds | 0 |

## Scheduler

| Metric | Current median | Baseline median | Change vs baseline | Unit | Failed |
| --- | ---: | ---: | ---: | --- | ---: |
| stress-ng switch | 19528911.88 | n/a | n/a | bogo ops/sec | 0 |
| stress-ng futex | 4837731.66 | n/a | n/a | bogo ops/sec | 0 |
| schbench p99 | 22112.00 | n/a | n/a | usec | 0 |
| hackbench | 0.2120 | n/a | n/a | seconds | 0 |
| cyclictest max | 11.000 | n/a | n/a | usec | 0 |

## Memory and filesystem

| Metric | Current median | Baseline median | Change vs baseline | Unit | Failed |
| --- | ---: | ---: | ---: | --- | ---: |
| stress-ng vm | 1406163.11 | n/a | n/a | bogo ops/sec | 0 |
| fio randread | 22265.92 | n/a | n/a | IOPS | 0 |
| fio randwrite | 753819.74 | n/a | n/a | IOPS | 0 |
| fio seqread | 10128.50 | n/a | n/a | IOPS | 0 |
| fio seqwrite | 6671.10 | n/a | n/a | IOPS | 0 |
