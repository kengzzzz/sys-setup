# Profiling notes

## AutoFDO

```sh
docker compose run --rm --build kernel-autofdo
# Install the kernel + NVIDIA packages from out/autofdo/, then boot linux-profiler.
docker compose run --rm --build autofdo
```

Keep that build's debug package in `out/autofdo/`. Collection checks it against
the running kernel, records 30 minutes of your normal workload, and replaces
`profiles/kernel.afdo`. Back up profiles you want to keep, then rebuild the final
kernel. If you change perf sysctls temporarily, restore their original values.

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
in `patches/kernel.patch`, update its config assertions, then rebuild.
Enabling the Compose file alone does not enable final optimization.

To disable it, undo those recipe/assertion changes and select `compose.yaml`.
Builds were tested; boot and real profile collection still need a manual check.
