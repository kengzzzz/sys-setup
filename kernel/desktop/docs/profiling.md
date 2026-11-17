# Profiling

Both profiles need broadcast-linux running and the NVIDIA Container Toolkit. A run
records `scripts/run-autofdo-workload.sh` and your desktop use with perf, in 5-minute
cycles, for 10 to 60 minutes. It stops when the profile density reaches 50 and a
cycle adds under 2% new entries.

## AutoFDO

```sh
docker compose run --rm --build kernel-autofdo
# Install the packages from out/autofdo/ and boot linux-profiler.
docker compose run --rm --build kernel-autofdo-profile
```

The result replaces `profiles/kernel.afdo`. Add `-e AUTOFDO_SMOKE=1` for a short test
that keeps the old profile.

## Propeller

```sh
docker compose run --rm --build kernel-propeller
# Install the packages from out/propeller/ and boot linux-profiler.
docker compose run --rm --build propeller
```

The result replaces `profiles/propeller_cc_profile.txt` and
`profiles/propeller_ld_profile.txt`. Add `-e PROPELLER_SMOKE=1` for a short test.

A Propeller profile only fits the build it came from. Collect a new one after you
change the source, `kernel.afdo`, clang or the config.

Path cloning is on. To turn it off, add `path_profile_options { enable_cloning: false }`
to `--propeller_options` in `scripts/generate-propeller-profile.sh`.
