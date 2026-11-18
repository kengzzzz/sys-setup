# Profiles

## AutoFDO

- File: `kernel.afdo`
- Collected: 2026-11-17 on `linux-profiler 7.3.5-1` (EEVDF, ThinLTO) with `kernel-autofdo-profile`, 20 min
- SHA-256: `4805f9be2768388f608ffc6a0bb8d1523382433d644c1f626d3565c0c94e082a`

## Propeller

- Files: `propeller_cc_profile.txt`, `propeller_ld_profile.txt`
- Collected: 2026-11-17 on `linux-profiler 7.3.5-1` (EEVDF, ThinLTO, the `kernel.afdo` above) with `propeller`, 25 min, path cloning on
- Profiled build ID: `6ff03be9331d8a4a1648f2b5d1cc2fdf1e0fe930`
- SHA-256 cc: `2f64b963caf0411b8fd84a96bd96f19e26cd701bbb91f1966b555e690b280d11`
- SHA-256 ld: `1a816f49710a9edb822900b7b5a3fd647001a03656c0fa30a546085c28228dd4`

Update this file when you replace a profile, then rebuild with `--build`. A new
`kernel.afdo` needs a new Propeller profile.
