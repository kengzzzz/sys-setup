# Profiles

## AutoFDO

- File: `kernel.afdo`
- Collected: 2026-11-08 on `linux-profiler 7.3.3-1` (EEVDF, ThinLTO) with `kernel-autofdo-profile`, 20 min
- SHA-256: `e924ab6ca6ed78f7897cb9585a34fa9918ccff108eaf12c5c6b70c9abeaa3b4f`

## Propeller

- Files: `propeller_cc_profile.txt`, `propeller_ld_profile.txt`
- Collected: 2026-11-11 on `linux-profiler 7.3.4-1` (EEVDF, ThinLTO, the `kernel.afdo` above) with `propeller`, 25 min, path cloning on
- Profiled build ID: `ce7887c1e71da4b7bbb2d8c08c30f06e722b8176`
- SHA-256 cc: `8e1efa253355d20cf7985f884d8757da9fe24c11c469715e63336b0127ec714a`
- SHA-256 ld: `d0300e654a7a293dfa0ea18000feab11a05414ae008ccce4559d38da5b7a52b8`

Update this file when you replace a profile, then rebuild with `--build`. A new
`kernel.afdo` needs a new Propeller profile.
