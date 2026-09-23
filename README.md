# dotfiles

Ghostty, Neovim, shell configurations and opt-in macOS preferences. The installer selects **zsh** or **bash** from the login shell (`$SHELL`), not the shell used to launch the script. On this Mac that selects zsh; on snowyserver-n100 it selects bash. Override with `--shell zsh` or `--shell bash` if needed.

## Install

```sh
gh repo clone snowykr/dotfiles "$HOME/.dotfiles"
"$HOME/.dotfiles/install.sh" --dry-run
"$HOME/.dotfiles/install.sh"
```

This repository is private: authenticate GitHub CLI on each machine before cloning, or use another authenticated Git transport. On snowyserver-n100, configure GitHub access and verify its host key before cloning over SSH.

The default run installs missing **Starship and eza first**, then links the selected shell configuration and Neovim. On macOS this uses Homebrew; on Ubuntu it uses `apt` for eza and Starship's official installer for Starship. If both commands already exist, no packages are changed. Ghostty is linked on macOS. Use `--no-packages` to link configurations without installing dependencies. Existing files **and directories** are moved into a timestamped directory under `~/.dotfiles-backups/` before linking; inspect the backup before deleting it. Re-running skips correct links. The other shell's startup file is left unchanged. Do not use `sudo` or pipe an unreviewed network script into a shell.

On macOS, install/update the listed Homebrew packages and apply the captured preferences explicitly:

```sh
"$HOME/.dotfiles/install.sh" --homebrew --macos --dry-run
"$HOME/.dotfiles/install.sh" --homebrew --macos
```

Install Homebrew from https://brew.sh/ first if it is missing. `--homebrew` installs the entire Brewfile (Ghostty, Neovim, fonts, search tools, Starship, eza); it is separate from the default minimal Starship/eza bootstrap. `--macos` without `--homebrew` applies only preferences in addition to the normal install. macOS preferences are skipped on Linux; requesting macOS-only steps there is an error. Neovim 0.11+ is required by the included configuration. The Neovim plugin manager bootstraps at first startup.

## Shell configuration

- `shell/zshrc` is based on the Mac's current `~/.zshrc`; `shell/bashrc` is based on snowyserver-n100's `~/.bashrc`. Shared shortcuts are in `shell/common.sh`.
- Startup files are symlinked into `$HOME`, and load `common.sh` from their symlink target. Host-specific or secret values belong in **untracked** `~/.zshrc.local` or `~/.bashrc.local`.
- Optional programs (pyenv, rbenv, nvm, starship, ble.sh, Bun completion) load only when installed. Destructive `fixperms` and forced Git restoration have not been carried over.
- The installer does not change the login shell. On a new host, set it separately with `chsh` only after confirming the desired shell is available.

## macOS preferences

`scripts/macos-defaults.sh` records settings read from the Mac at the time this repo was assembled: dark appearance; Dock auto-hide, zero delay, 0.5-second animation, 44-pixel icons and no recent apps; Finder path bar and all filename extensions. It checks existing values and only writes differences, then restarts Dock/Finder at most once each. Review with `scripts/macos-defaults.sh --dry-run`. Dark appearance can require signing out and back in for all apps to update. Dock pinned apps, keyboard/input sources, security settings, and wallpaper are intentionally not reset.

## Verify

Run `sh scripts/test-install.sh` and `sh scripts/test-install-tools.sh` to exercise backups, repeat installs, shell selection, macOS preference changes, and first-run packages without modifying the host. Run `./install.sh --dry-run --macos` on a Mac before applying preferences.

The old `ghostty-config` and `nvim-config` repositories remain untouched as historical sources. The source for Neovim includes the locally modified `lazy-lock.json` from migration day; inspect it when updating plugins.
