# Profile input

- File: `kernel.afdo`
- Collected: 2026-11-08 on `linux-profiler 7.3.3-1` (EEVDF, ThinLTO) with `kernel-autofdo-profile`, 20 min
- SHA-256: `e924ab6ca6ed78f7897cb9585a34fa9918ccff108eaf12c5c6b70c9abeaa3b4f`

- Files: `propeller_cc_profile.txt`, `propeller_ld_profile.txt`
- Collected: 2026-11-08 on `linux-profiler 7.3.3-1` (EEVDF, ThinLTO, the `kernel.afdo` above) with `propeller`, 30 min, path cloning on
- Profiled build ID: `7e8f9e7bcb4c61dc30e8e14b4737a1a1f7cf0dfc`
- SHA-256 cc: `975b89158d71ad8ed0f836bd26f0f25538f460817396cff4b4aa7ae018092179`
- SHA-256 ld: `28df32a13f3ae1e5cd0ef1ea212a3dee791310f7172dcd65a8bd6e9face6b1e0`

Update this when replacing, then rebuild with `--build`. Recollect Propeller
after replacing `kernel.afdo`.
