# Desktop kernel

BORE + FullLTO + AutoFDO for my Ryzen/NVIDIA desktop.

## Build

From this directory, using Docker Compose:

```sh
docker compose run --rm --build kernel-config   # config-only
docker compose run --rm --build kernel-builder
```

Packages and `kernel.config` go to `out/kernel/`. Move old packages elsewhere
before rebuilding the same version. `.env` sets pins and the tmpfs size (64G).

Edit `patches/` for scheduler/LTO/profile/package choices, and
`scripts/configure-kernel.sh` for hardware settings and matching assertions.
Keep collection recipes aligned. Profile inputs live in `profiles/`;
use `--build` after changing inputs. See [profiling](docs/profiling.md).

## Install

Use the exact kernel and NVIDIA package paths printed by the build:

```sh
sudo pacman -U ./out/kernel/linux-bore-flto-pgo-7.2.5-1-x86_64.pkg.tar.zst \
  ./out/kernel/linux-bore-flto-pgo-nvidia-open-7.2.5-1-x86_64.pkg.tar.zst
```

Adjust the version for later builds. Headers are only needed for external
module builds/DKMS. Check the boot entry and run `sudo mkinitcpio -P` after
preset changes; keep a fallback kernel.
