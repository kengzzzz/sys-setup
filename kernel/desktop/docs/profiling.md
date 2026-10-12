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

Update `profiles/README.md`, then rebuild the final kernel.

Defaults: `-e AUTOFDO_DENSITY=50 -e AUTOFDO_PLATEAU=2 -e AUTOFDO_MAX_MINUTES=60`.
Smoke test (a few minutes, keeps the profile):

```sh
docker compose run --rm --build -e AUTOFDO_SMOKE=1 kernel-autofdo-profile
```

## Propeller

In `.env`, set `COMPOSE_FILE=compose.yaml:compose.propeller.yaml` and uncomment
the converter pins (`PROPELLER_REF`, `UBUNTU_IMAGE_DIGEST`, `LLVM_GPG_FINGERPRINT`).

```sh
docker compose run --rm --build kernel-propeller
# Install from out/propeller/, boot that linux-profiler build, then:
docker compose run --rm --build propeller
```

Keep its debug package in `out/propeller/`. This collection recipe uses ThinLTO
and the AutoFDO input; conversion writes `profiles/propeller_{cc,ld}_profile.txt`.
For final use, select ThinLTO, `_propeller=yes`, and `_propeller_profiles=yes`
in `patches/variants/kernel.patch`, update its config assertions, then rebuild.
Enabling the Compose file alone does not enable final optimization.

To disable it, undo those recipe/assertion changes and select `compose.yaml`.
Builds were tested; boot and real profile collection still need a manual check.
