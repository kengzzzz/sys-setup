# Zed setup

These scripts install the Zed config from the `dotfiles` repo, `zed/.config/zed`.

## Linux

```bash
./zed/install-linux.sh           # links the tracked files from ~/dotfiles
./zed/install-linux.sh --adopt   # first run: moves the current config into the dotfiles
```

Set `DOTFILES_DIR` if the dotfiles are elsewhere.

## Windows

From the `sys-setup` checkout inside WSL:

```bash
./zed/install-windows-from-wsl.sh
```

It copies the config to `%APPDATA%\Zed` and backs up replaced files. Run it again
after you update the dotfiles.

With the dotfiles on the Windows filesystem, link them instead:

```powershell
.\zed\install-windows.ps1 -SourceDir C:\path\to\dotfiles\zed\.config\zed
```

Pass `-Copy` if you have neither Developer Mode nor admin rights.
