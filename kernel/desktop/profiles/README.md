# Profile input

- File: `kernel.afdo`
- Collected: 2026-08-20 on `linux-bore-flto-pgo 7.2.0-1`
- Recipe: `kernel-autofdo` -> boot `linux-profiler` -> `autofdo`
- Workload: mixed desktop — GPU-intensive gaming, CPU-intensive parallel build, disk I/O, streaming video playback
- Toolchain: builder runs `pacman -Syu`, not pinned
- SHA-256: `8729c3755ea4ebc94f824295e03d20f89dedbdd2775c490b48e7d6980f394f9e`

Update this when replacing, then rebuild with `--build`.
