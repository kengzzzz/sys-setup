# Compile AutoFDO Kernel

- `docker compose run --rm kernel-autofdo`

# Install AutoFDO Kernel & Reboot

- `sudo pacman -U --overwrite '*' ./out/autofdo/linux-profiler*.pkg.tar.zst`
- config your bootloader
- reboot to autofdo kernel

# Prepare AutoFDO

- `sudo sh -c "echo 0 > /proc/sys/kernel/kptr_restrict"`
- `sudo sh -c "echo 0 > /proc/sys/kernel/perf_event_paranoid"`
- `docker compose build autofdo`

# Workload AutoFDO

- burn your CPU around 30 mins
- **while burning** run `docker compose run --rm autofdo`

# Compile Propeller Kernel

- `docker compose run --rm kernel-propeller`

# Install Propeller Kernel & Reboot

- `sudo pacman -U --overwrite '*' ./out/propeller/linux-profiler*.pkg.tar.zst`
- config your bootloader
- reboot to propeller kernel

# Prepare Propeller

- `sudo sh -c "echo 0 > /proc/sys/kernel/kptr_restrict"`
- `sudo sh -c "echo 0 > /proc/sys/kernel/perf_event_paranoid"`
- `docker compose build propeller`

# Workload Propeller

- burn your CPU around 30 mins
- **while burning** run `docker compose run --rm propeller`

# Create Config

- `docker compose run --rm kernel-config`

# Compile Kernel

- `docker compose run --rm kernel-builder`

# Prepare Installation

- update `/etc/mkinitcpio.d/linux-eevdf-lto-prop.preset` add `default_options="-S autodetect"`

# Installation

- `sudo pacman -U --overwrite '*' ./out/linux-eevdf-lto-prop*.pkg.tar.zst`

# Clean up profiler

- `sudo pacman -Rns linux-profiler linux-profiler-headers linux-profiler-dbg linux-profiler-nvidia-open`