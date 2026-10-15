# Profile input

- File: `kernel.afdo`
- Collected: 2026-10-15 on `linux-profiler 7.2.11-1` (EEVDF, ThinLTO) with `kernel-autofdo-profile`, 15 min
- SHA-256: `1f0dea3d39acc9d18086a2959798a1a42285e22f0421a6f955d281621f11c438`

- Files: `propeller_cc_profile.txt`, `propeller_ld_profile.txt`
- Collected: 2026-10-15 on `linux-profiler 7.2.11-1` (EEVDF, ThinLTO, the `kernel.afdo` above) with `propeller`, 30 min, 281 clone paths
- Profiled build ID: `d5f5eee25194a1abf632776c9aa7245b7aaca0ed`
- SHA-256 cc: `09b73af360c103eae28e3cbb1cc60e827c0f246d18bfe2ea1cdd1deccbc94ceb`
- SHA-256 ld: `f6a2612e3c30a46269b4145326baee09474833f4a08331aa4edd3467680e34aa`

Update this when replacing, then rebuild with `--build`. Recollect Propeller
after replacing `kernel.afdo`.
