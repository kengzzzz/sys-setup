# WSL2 + Debian setup

Stand up a fresh WSL2 Debian dev box from a Windows host: install WSL2, register
Debian as the default distro with systemd enabled, create the user, then clone
this repo inside the distro and run [`provision.sh`](provision.sh) to install the
zsh shell environment and the private dotfiles.

```
wsl2.ps1    (Windows host, PowerShell)  →  provision.sh  (inside Debian, as root)
```

## Prerequisites

- Windows 10 21H2+ or Windows 11.
- An **elevated** PowerShell (Run as Administrator) — first-time WSL feature
  enablement needs it.
- For dotfiles: your **YubiKey** (the FIDO `sk-ssh-ed25519` key registered to
  GitHub) and the Windows **OpenSSH Client** (`ssh-add`). The script loads the
  key into the Windows ssh-agent and forwards that agent into the distro, so the
  private `git@github.com:kengzzzz/dotfiles.git` can be cloned without copying any
  key material into WSL.

## Run it

From an elevated PowerShell:

```powershell
irm https://raw.githubusercontent.com/kengzzzz/sys-setup/main/wsl2.ps1 -OutFile wsl2.ps1
powershell -ExecutionPolicy Bypass -File .\wsl2.ps1
```

Useful flags:

```powershell
.\wsl2.ps1 -WslUser keng                 # UNIX username to create (default: keng)
.\wsl2.ps1 -InstanceName DebianTest       # throwaway instance alongside your real Debian (needs WSL 2.4.4+)
.\wsl2.ps1 -SkipDotfiles                  # shell environment only, no clone
.\wsl2.ps1 -NpiperelayPath C:\tools\npiperelay.exe
```

## What it does

`wsl2.ps1` (Windows host):

1. Verifies elevation and that WSL2 is available (installs the platform and asks
   for a reboot if not).
2. Unless `-SkipDotfiles`: starts the Windows `ssh-agent`, runs `ssh-add -K` to
   load the YubiKey resident key, and downloads `npiperelay.exe` if missing.
3. `wsl --install -d Debian --no-launch`, `--set-default-version 2`, makes it the
   default distro.
4. Creates the user (prompts for a password), writes `/etc/wsl.conf`
   (`[boot] systemd=true`, `[user] default=<user>`), and terminates the distro to
   apply.
5. Clones this repo to `/opt/sys-setup` and runs `provision.sh`.

`provision.sh` (inside Debian, as root):

1. Installs `zsh git stow build-essential curl ca-certificates locales socat sudo
   gnupg` and generates the `en_US.UTF-8` locale.
2. `loginctl enable-linger` so the user systemd manager (and the agent bridge)
   run without an interactive login.
3. Installs oh-my-zsh and the three plugins the dotfiles load
   (`zsh-autosuggestions`, `zsh-syntax-highlighting`, `fast-syntax-highlighting`).
   The theme is `robbyrussell` (built into oh-my-zsh — no theme install needed).
4. Installs the CLI tools the dotfiles' aliases assume: `eza` (`ls`/`ll`/`lt`),
   `fastfetch` (`ff`, plus the shell banner), and `nano` (`$EDITOR`). On Debian
   releases without these in apt, it falls back to the upstream eza repo and the
   fastfetch `.deb`.
5. Brings up the forwarded ssh-agent bridge (`socat` + `npiperelay.exe` →
   `~/.ssh/agent.sock`) and verifies `ssh -T git@github.com`.
6. Clones `kengzzzz/dotfiles` and links it with `stow` (skipping the Arch/system
   dirs `utils`, `etc`, `usr`).
7. Writes `~/.zshrc_custom` (sourced last by the dotfiles' `.zshrc`) to point
   `SSH_AUTH_SOCK` at the bridge socket — the dotfiles' `00-init` otherwise sets
   the Arch desktop path `$XDG_RUNTIME_DIR/ssh-agent.socket`.
8. Installs the persistent `wsl-ssh-agent.service` user unit and sets `zsh` as the
   login shell.

## Notes

- **Idempotent.** Re-running skips the distro install, the user, and existing
  clones; it re-provisions in place. Safe to run again after a failure.
- **Throwaway test instance.** `-InstanceName DebianTest` registers the same Debian
  base under a separate name (needs WSL 2.4.4+ for `--install --name`), so you can
  rehearse the whole flow without touching your real distro. The test instance is
  **not** made the default and is removed with `wsl --unregister DebianTest`; pass
  `-DistroName` too only if you want a different base distro.
- **No YubiKey / agent down.** Dotfiles are skipped with guidance; the rest of the
  shell environment still installs. Plug in the key, run `ssh-add -K` on Windows,
  and re-run to finish.
- **Vanilla kernel.** Stock Microsoft WSL2 kernel; no `.wslconfig` tuning and no
  custom kernel (see `../kernel/deprecated/wsl2/` for the experimental kernel
  build).
- **Shell only.** Dev toolchains (nvm/node, bun, go, rust, docker) are not
  installed; the matching `PATH` lines in the dotfiles' `.zshrc` simply no-op when
  those tools are absent.
- **Other machines.** `--win-user` is auto-detected from `/mnt/c/Users`; pass it
  (and `-NpiperelayPath`) explicitly on a host where the Windows username differs.
