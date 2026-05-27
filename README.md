# sys-setup

Personal system setup scripts for Arch Linux, custom kernels, and local
performance/container experiments.

## Arch Linux install

Boot an Arch ISO, connect networking, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/kengzzzz/sys-setup/main/archlinux.sh | bash
```

The installer is opinionated for my workstation: custom `linux-bore-flto-pgo`
primary kernel, CachyOS LTS fallback kernel, systemd-networkd, systemd-boot,
Hyprland desktop packages, YubiKey PAM auth, and private dotfiles setup.

## Local checks

```bash
bash -n archlinux.sh archlinux/install.sh archlinux/chroot.sh archlinux/lib/*.sh archlinux/tests/run.sh
archlinux/tests/run.sh
archlinux/install.sh --help
```

Use `archlinux/install.sh --dry-run` to inspect prompts and the selected plan
without building the kernel or touching disks.
