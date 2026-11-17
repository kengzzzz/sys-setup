# WSL2 Debian setup

`wsl2.ps1` installs WSL2 and Debian with systemd, creates the user, then runs
[`provision.sh`](provision.sh) inside Debian. That sets up zsh, Oh My Zsh, eza,
fastfetch and the dotfiles' `btop`, `codex`, `fastfetch`, `muse`, `ssh` and `zshrc`
Stow packages.

## Requirements

- Windows 10 21H2 or later, and an elevated PowerShell.
- For the dotfiles: the YubiKey with the GitHub SSH key, and the Windows OpenSSH
  Client. The script forwards the Windows ssh-agent into Debian, so no key is copied.

## Run

```powershell
irm https://raw.githubusercontent.com/kengzzzz/sys-setup/main/wsl2.ps1 -OutFile wsl2.ps1
powershell -ExecutionPolicy Bypass -File .\wsl2.ps1
```

Options:

```powershell
.\wsl2.ps1 -WslUser keng            # default keng
.\wsl2.ps1 -InstanceName DebianTest  # separate test distro, needs WSL 2.4.4+
.\wsl2.ps1 -SkipDotfiles             # shell only
.\wsl2.ps1 -NpiperelayPath C:\tools\npiperelay.exe
```

## Notes

- Running it again is safe. It skips what exists.
- Without the YubiKey, it skips the dotfiles. Run `ssh-add -K` on Windows and run it
  again.
- Remove a test distro with `wsl --unregister DebianTest`.
- `provision.sh` finds the Windows user in `/mnt/c/Users`. Pass `--win-user` if it
  guesses wrong.
