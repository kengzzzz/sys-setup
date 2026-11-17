# Desktop kernel

EEVDF with ThinLTO, AutoFDO and Propeller, for my Ryzen and NVIDIA desktop.

## Build

```sh
docker compose run --rm --build kernel-config   # config only
docker compose run --rm --build kernel-builder
```

Packages go to `out/kernel/`. `.env` holds the version pins, `patches/` the kernel
changes, and `scripts/configure-kernel.sh` the hardware options. After a kernel
update, collect a new Propeller profile. See [profiling](docs/profiling.md).

## Install

```sh
sudo pacman -U ./out/kernel/linux-eevdf-lto-prop-[0-9]*-x86_64.pkg.tar.zst \
  ./out/kernel/linux-eevdf-lto-prop-nvidia-open-[0-9]*-x86_64.pkg.tar.zst
```

Keep one version in `out/kernel/` so the globs match one file. Keep a fallback kernel.
