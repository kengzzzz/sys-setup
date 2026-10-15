# Profiling notes

## AutoFDO

```sh
docker compose run --rm --build kernel-autofdo
# Install the kernel + NVIDIA packages from out/autofdo/, add a boot entry, boot linux-profiler.
docker compose run --rm --build kernel-autofdo-profile
```

Needs that build's debug package in `out/autofdo/`, broadcast-linux running, and
the NVIDIA Container Toolkit.

Collection checks the booted kernel against the debug `vmlinux`, then records
`scripts/run-autofdo-workload.sh` with system-wide perf in 5-minute cycles. It
stops when profile density reaches 50 and a cycle adds under 2% new entries
(10–60 min), then replaces `profiles/kernel.afdo`. Desktop use during the run is
profiled too. Each cycle uses ~300 MB of network. `kernel.kptr_restrict=2` is
lowered to 1 until exit.

Defaults: `-e AUTOFDO_DENSITY=50 -e AUTOFDO_PLATEAU=2 -e AUTOFDO_MAX_MINUTES=60`.
Smoke test (a few minutes, keeps the profile):

```sh
docker compose run --rm --build -e AUTOFDO_SMOKE=1 kernel-autofdo-profile
```

## Propeller

```sh
docker compose run --rm --build kernel-propeller
# Install the kernel + NVIDIA packages from out/propeller/, boot linux-profiler.
docker compose run --rm --build -e PROPELLER_SMOKE=1 propeller   # smoke test
docker compose run --rm --build propeller
```

Same requirements, workload and stopping rule as AutoFDO (`PROPELLER_*`
variables). The profiler is ThinLTO + `kernel.afdo`; output goes to
`profiles/propeller_{cc,ld}_profile.txt`.

Profiles only match that exact build: recollect after changing the source,
`kernel.afdo`, clang or config, then build `kernel-builder`.

Path cloning is on ("clone paths" in the cycle summary). To disable it, add
`path_profile_options { enable_cloning: false }` to `--propeller_options` in
`scripts/generate-propeller-profile.sh`.
