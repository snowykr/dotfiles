# dotfiles

Personal shell, editor, terminal, and macOS setup.

## Install

This repository is private. Install [Homebrew](https://brew.sh/) and run `brew install gh` on macOS, or run `sudo apt-get update && sudo apt-get install -y gh` on Ubuntu.

```sh
gh auth login --hostname github.com --git-protocol https --web
gh auth setup-git
gh repo clone snowykr/dotfiles "$HOME/.dotfiles"
"$HOME/.dotfiles/install.sh" --dry-run
"$HOME/.dotfiles/install.sh"
```

The installer detects the login shell, installs missing CLI tools, sets Git identity, and links the configuration. Existing files are backed up under `~/.dotfiles-backups/`. Use `--no-packages` to skip CLI installation.

To review and apply macOS preferences:

```sh
"$HOME/.dotfiles/scripts/macos-defaults.sh" --dry-run
"$HOME/.dotfiles/scripts/macos-defaults.sh"
```

To install macOS apps as well, run `"$HOME/.dotfiles/install.sh" --homebrew --macos`.

## Contents

- `shell/` — zsh, bash, and shared shell settings.
- `config/` — Ghostty and Neovim settings.
- `Brewfile` — macOS apps and CLI dependencies.
- `scripts/` — macOS preferences and installation tests.

## Test

```sh
sh scripts/test-install.sh
sh scripts/test-install-tools.sh
```
