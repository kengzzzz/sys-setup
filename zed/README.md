# Zed setup

Zed configuration is stored in the separate `dotfiles` repository under
`zed/.config/zed`. These scripts install that configuration without putting
machine setup logic in the dotfiles repository.

## Linux

With the dotfiles checkout at `~/dotfiles`:

```bash
./zed/install-linux.sh
```

To capture and link an existing config on the first run:

```bash
./zed/install-linux.sh --adopt
git -C ~/dotfiles diff -- zed
```

Set `DOTFILES_DIR` when the checkout is elsewhere. Only tracked Zed entries are
linked, so `~/.config/zed` remains a real directory.

## Windows through WSL2

Windows does not need Git. Clone both repositories inside WSL, then run from the
`sys-setup` checkout:

```bash
./zed/install-windows-from-wsl.sh
```

The wrapper uses WSL interop to run Windows PowerShell and copies the tracked
configuration into `%APPDATA%\Zed`. Rerun it after updating the dotfiles. Files
that would be replaced are moved to `%APPDATA%\Zed.dotfiles-backup.*` first.

Copying is intentional: a native Windows editor should not depend on a
`\\wsl.localhost` symlink being available at startup.

## Native Windows checkout

If the dotfiles are also available on the Windows filesystem, run:

```powershell
.\zed\install-windows.ps1 -SourceDir C:\path\to\dotfiles\zed\.config\zed
```

This creates symlinks by default. Use `-Copy` when Windows Developer Mode and
administrator access are unavailable.
