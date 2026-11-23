# Profiles

## AutoFDO

- File: `kernel.afdo`
- Collected: 2026-11-17 on `linux-profiler 7.3.5-1` (EEVDF, ThinLTO) with `kernel-autofdo-profile`, 20 min
- SHA-256: `4805f9be2768388f608ffc6a0bb8d1523382433d644c1f626d3565c0c94e082a`

## Propeller

- Files: `propeller_cc_profile.txt`, `propeller_ld_profile.txt`
- Collected: 2026-11-23 on `linux-profiler 7.3.6-1` (EEVDF, ThinLTO, the `kernel.afdo` above) with `propeller`, 25 min, path cloning on
- Profiled build ID: `7260299586d2a232d63e4adeea60f817cba4eb07`
- SHA-256 cc: `9490e51d28ed1c4743227262c375b37fa560f63e76846c81cc2af882b02affb5`
- SHA-256 ld: `f2c801ba49423f14fa8666cfd05a89a431aab3b8845eed1fa1420bad5bfa36ab`

Update this file when you replace a profile, then rebuild with `--build`. A new
`kernel.afdo` needs a new Propeller profile.
