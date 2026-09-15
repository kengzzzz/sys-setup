# sys-setup

Personal Arch Linux, WSL2 and kernel setup scripts.

## Arch Linux

Boot an Arch ISO in UEFI mode with Secure Boot disabled and networking connected:

```sh
curl -fsSL https://raw.githubusercontent.com/kengzzzz/sys-setup/main/archlinux.sh | bash
```

Sets up my workstation: Hyprland/Quickshell, systemd-boot, static networking,
YubiKey authentication, dotfiles, and a custom kernel with a CachyOS LTS fallback.

From a local checkout, use `bash archlinux/install.sh --dry-run` to preview the
installation, or `--help` for options.

## WSL2 + Debian

Run in elevated PowerShell:

```powershell
irm https://raw.githubusercontent.com/kengzzzz/sys-setup/main/wsl2.ps1 -OutFile wsl2.ps1
powershell -ExecutionPolicy Bypass -File .\wsl2.ps1
```

See [WSL2 setup](wsl2/README.md) for prerequisites and configuration.

## Kernels

- [Desktop build and install](kernel/desktop/README.md) — packages in `kernel/desktop/out/kernel/`.
- [AutoFDO / Propeller profiling](kernel/desktop/docs/profiling.md).
- [Raspberry Pi and benchmarks](kernel/README.md).
