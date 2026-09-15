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

Build prints `Package: /out/kernel/...` (use `./out/kernel/...` on the host):

```sh
sudo pacman -U ./out/kernel/linux-bore-flto-pgo-[0-9]*-x86_64.pkg.tar.zst \
  ./out/kernel/linux-bore-flto-pgo-nvidia-open-[0-9]*-x86_64.pkg.tar.zst
```

Keep only one version in `out/kernel/` for globs, else use exact filenames. Headers are only needed for external
module builds/DKMS. Check the boot entry and run `sudo mkinitcpio -P` after
preset changes; keep a fallback kernel.
