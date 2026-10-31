# Profile input

- File: `kernel.afdo`
- Collected: 2026-10-21 on `linux-profiler 7.3.0-2` (EEVDF, ThinLTO) with `kernel-autofdo-profile`, 25 min
- SHA-256: `625292ade9bea773d0b116d8bf1d928966cb0e959edd75b60cf6b0a90c26b28b`

- Files: `propeller_cc_profile.txt`, `propeller_ld_profile.txt`
- Collected: 2026-10-31 on `linux-profiler 7.3.1-1` (EEVDF, ThinLTO, the `kernel.afdo` above) with `propeller`, 25 min, path cloning off
- Profiled build ID: `06f8e1db60fb17bbbf1fef57f709859b35e2fada`
- SHA-256 cc: `3940adebee7fc77cc42783c86a6f9e9618f649526e870e5cf05951f3d21ddd52`
- SHA-256 ld: `4ce3c985057053e7487ea0d87ea939be6c0c93f9927e1be501ae2a06f2a0a569`

Update this when replacing, then rebuild with `--build`. Recollect Propeller
after replacing `kernel.afdo`.
