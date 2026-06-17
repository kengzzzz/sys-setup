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

## WSL2 + Debian

Stand up a fresh WSL2 Debian dev box from a Windows host. From an **elevated**
PowerShell:

```powershell
irm https://raw.githubusercontent.com/kengzzzz/sys-setup/main/wsl2.ps1 -OutFile wsl2.ps1
powershell -ExecutionPolicy Bypass -File .\wsl2.ps1
```

`wsl2.ps1` installs WSL2 + Debian (default, systemd on, stock kernel),
creates the user, then runs `wsl2/provision.sh` inside the distro to install the
zsh shell environment and clone/stow the private dotfiles over a forwarded
Windows ssh-agent (YubiKey). See [`wsl2/README.md`](wsl2/README.md).

## Local checks

```bash
bash -n archlinux.sh archlinux/install.sh archlinux/chroot.sh lib/*.sh archlinux/lib/*.sh archlinux/tests/run.sh wsl2/provision.sh
archlinux/tests/run.sh
archlinux/install.sh --help
wsl2/provision.sh --help
```

Use `archlinux/install.sh --dry-run` to inspect prompts and the selected plan
without building the kernel or touching disks.
