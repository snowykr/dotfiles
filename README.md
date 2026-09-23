# dotfiles

Ghostty, Neovim, shell, and macOS settings.

## Install

This repository is private. Install GitHub CLI first: `brew install gh` on macOS (requires [Homebrew](https://brew.sh/)), or `sudo apt-get update && sudo apt-get install -y gh` on Ubuntu.

```sh
gh auth login --hostname github.com --git-protocol https --web
gh auth setup-git
gh repo clone snowykr/dotfiles "$HOME/.dotfiles"
"$HOME/.dotfiles/install.sh" --dry-run
"$HOME/.dotfiles/install.sh"
```

The installer links `.zshrc` or `.bashrc` according to the login shell (`$SHELL`), plus Neovim configuration. On macOS it also links Ghostty configuration. Existing files and directories are backed up under `~/.dotfiles-backups/`; correct links are skipped on repeat runs. Use `--shell zsh` or `--shell bash` to override shell selection.

Missing `starship`, `eza`, and `gh` are installed automatically. The installer also sets global Git `user.name=snowykr` and `user.email=snowykr22@gmail.com`. Use `--no-packages` to skip package installation. On Ubuntu, packages use `apt`; Starship uses its official installer into `~/.local/bin`.

To install the remaining macOS apps and tools from `Brewfile` and apply system settings:

```sh
"$HOME/.dotfiles/install.sh" --homebrew --macos --dry-run
"$HOME/.dotfiles/install.sh" --homebrew --macos
```

## Configuration

- **Shell:** shared Git/development shortcuts (`gmg` runs `git merge`), optional tool initialization, and local overrides (`~/.zshrc.local` / `~/.bashrc.local`).
- **Neovim:** `lazy.nvim`, plugins, and `lazy-lock.json`. Requires Neovim 0.11+.
- **Ghostty:** fonts, colors, and terminal behavior.
- **macOS:** dark appearance; Dock auto-hide, zero delay, 0.5-second animation, 44-pixel icons, and hidden recent apps; Finder path bar and filename extensions. Unchanged values are skipped; Dock/Finder restart only when needed.

## Verify

```sh
sh scripts/test-install.sh
sh scripts/test-install-tools.sh
```
