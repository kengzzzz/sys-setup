# Compile AutoFDO Kernel

- `docker compose run --rm kernel-autofdo`

# Install AutoFDO Kernel & Reboot

- ```sh
  sudo pacman -U --overwrite '*' \
    ./out/autofdo/linux-profiler-[0-9]*.pkg.tar.zst \
    ./out/autofdo/linux-profiler-nvidia-open-[0-9]*.pkg.tar.zst
  ```
- config your bootloader
- reboot to autofdo kernel

# Prepare AutoFDO

- `sudo sh -c "echo 0 > /proc/sys/kernel/kptr_restrict"`
- `sudo sh -c "echo 0 > /proc/sys/kernel/perf_event_paranoid"`
- `docker compose build autofdo`

# Workload AutoFDO

- burn your CPU around 30 mins
- **while burning** run `docker compose run --rm autofdo`

# Create Config

- `docker compose run --rm kernel-config`

# Compile Kernel

- `docker compose run --rm kernel-builder`

# Prepare Installation

- update `/etc/mkinitcpio.d/linux-bore-flto-pgo.preset` add `default_options="-S autodetect"`

# Installation

- ```sh
  sudo pacman -U --overwrite '*' \
    ./out/linux-bore-flto-pgo-[0-9]*.pkg.tar.zst \
    ./out/linux-bore-flto-pgo-nvidia-open-[0-9]*.pkg.tar.zst
  ```

> Install only the kernel and the nvidia module. The `-[0-9]` anchors the glob to
> the version field so `-headers` and `-dbg` are skipped: `-headers` hard-depends
> on `clang llvm lld`, which pulls ~500 MiB of toolchain back onto a host that
> otherwise needs no compiler. Nothing here builds out-of-tree modules — the
> nvidia module is built in-container by `kernel-builder` — so the headers are
> dead weight. Install them only if you add a DKMS module later.

# Clean up profiler

- `sudo pacman -Rns linux-profiler linux-profiler-nvidia-open`

  (add `linux-profiler-headers linux-profiler-dbg` if you installed them)
