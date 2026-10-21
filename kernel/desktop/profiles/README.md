# Profile input

- File: `kernel.afdo`
- Collected: 2026-10-21 on `linux-profiler 7.3.0-2` (EEVDF, ThinLTO) with `kernel-autofdo-profile`, 25 min
- SHA-256: `625292ade9bea773d0b116d8bf1d928966cb0e959edd75b60cf6b0a90c26b28b`

- Files: `propeller_cc_profile.txt`, `propeller_ld_profile.txt`
- Collected: 2026-10-21 on `linux-profiler 7.3.0-2` (EEVDF, ThinLTO, the `kernel.afdo` above) with `propeller`, 20 min, 266 clone paths
- Profiled build ID: `5ff946759fc94f28548ccf2d5c6e27e4548c8140`
- SHA-256 cc: `a9d21008dc45e348a6df7f71108299395dd79bbc6c44257b39ae162b4dac65f5`
- SHA-256 ld: `4b8d951bb8f359cac4bd545ce5639fbe798c8087e7f5df82b7066e9d3b4bef9d`

Update this when replacing, then rebuild with `--build`. Recollect Propeller
after replacing `kernel.afdo`.
