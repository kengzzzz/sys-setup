# sys-setup

Setup scripts for my Arch Linux workstation, a WSL2 Debian box and custom kernels.

## Arch Linux

Boot an Arch ISO in UEFI mode with Secure Boot off and a network connection, then run:

```sh
curl -fsSL https://raw.githubusercontent.com/kengzzzz/sys-setup/main/archlinux.sh | bash
```

It installs Hyprland with [deskshell](https://github.com/kengzzzz/deskshell), Limine,
YubiKey login, the dotfiles and a custom kernel on Btrfs. Hyprland, aquamarine,
egl-wayland2 and FreeRDP come from [patched-pkgs](https://github.com/kengzzzz/patched-pkgs).
A patched package that does not match the system's libraries stays stock. deskshell
and the patched packages are built for znver5.

`bash archlinux/install.sh --dry-run` previews the install. See
[recovery](archlinux/RECOVERY.md).

To save desktop preferences into the private `workstation` Stow package, run
`python archlinux/scripts/workstation-preferences.py save`.

If the dotfiles have `utils/scripts/setup-tenant.sh`, Steam runs as a separate
`tenant` user. Set its Steam compatibility tool, shader and download options after
the first login.

## WSL2 Debian

In an elevated PowerShell:

```powershell
irm https://raw.githubusercontent.com/kengzzzz/sys-setup/main/wsl2.ps1 -OutFile wsl2.ps1
powershell -ExecutionPolicy Bypass -File .\wsl2.ps1
```

See [WSL2 setup](wsl2/README.md).

## Other

- [Zed setup](zed/README.md)
- [Kernels](kernel/README.md)
- [llama.cpp server](llama.cpp/README.md)
