# dotfiles

Personal shell, editor, terminal, and platform-aware macOS/Linux setup.

## Install

This repository is private. Install [Homebrew](https://brew.sh/) and run `brew install gh` on macOS, or run `sudo apt-get update && sudo apt-get install -y gh` on Ubuntu.

```sh
gh auth login --hostname github.com --git-protocol https --web
gh auth setup-git
gh repo clone snowykr/dotfiles "$HOME/.dotfiles"
"$HOME/.dotfiles/install.sh" --dry-run
"$HOME/.dotfiles/install.sh"
```

The installer detects the OS with `uname -s` and selects configuration independently of the current login shell:

| Setting | macOS | Linux |
| --- | --- | --- |
| Shell configuration | `~/.zshrc` | `~/.bashrc` |
| Neovim configuration | Linked | Linked |
| Ghostty configuration | Linked | Unchanged |
| Appearance, Dock, Finder | Applied automatically | Skipped |
| System/display automatic sleep | Disabled on all power sources | Unchanged |
| CLI installation | Homebrew | apt-get (Ubuntu/Debian) + official Starship installer |

Missing CLI tools are installed: Neovim, ripgrep, fd, Starship, eza, gh, and lsof. Package names are mapped to their executables (`neovim` → `nvim`, `ripgrep` → `rg`); Linux uses `fd-find` → `fdfind`. macOS zsh settings resolve the Homebrew prefix for both Apple Silicon and Intel Macs.

Git identity is set to `snowykr` / `snowykr22@gmail.com`. Existing files are backed up under `~/.dotfiles-backups/`. Repeated installs leave matching symlinks and preferences unchanged. `--dry-run` previews changes without applying them.

Options:

- `--no-packages`: skip CLI installation. On Linux distributions without apt-get, install the listed tools manually and use this option.
- `--no-macos`: leave macOS appearance, clock, Dock, Finder, and power settings unchanged.
- `--shell zsh|bash`: override the OS-selected shell configuration.
- `--homebrew`: additionally install macOS apps and fonts from `Brewfile` (macOS only).

The installer links shell configuration but does **not** change the login shell with `chsh`. Open a matching shell or source its configuration after installation.

macOS preferences include Dark appearance, system-default appearance overrides, a digital 24-hour menu bar clock with seconds (no AM/PM label), an auto-hiding Dock, and Finder path/file-extension display. Existing clock date/day display options are preserved; clock changes restart ControlCenter to refresh the menu bar. To review or apply just those preferences:

```sh
"$HOME/.dotfiles/scripts/macos-defaults.sh" --dry-run
"$HOME/.dotfiles/scripts/macos-defaults.sh"
```

macOS setup also disables automatic system and display sleep on battery and external power (`sudo pmset -a sleep 0 displaysleep 0`). This disables idle sleep timers; it does not prevent loginwindow from explicitly turning off the display when locking. A dark lock screen is not evidence that the system has slept. Lock-screen display behavior must be verified separately on the target Mac. Power settings are checked first: `--dry-run` never invokes sudo, and already configured Macs do not need sudo for this step. Applying a power change requires administrator authentication; other power settings and lock-screen authentication are unchanged. Closing the lid, explicitly choosing Sleep, or running out of battery can still suspend the Mac. Keeping the display on increases battery use; connect power for long-running work.

To install macOS apps as well, run `"$HOME/.dotfiles/install.sh" --homebrew`. Linux never runs macOS preference commands.

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

Tests mock both operating systems, package managers, macOS preference writes, and pmset/sudo; they do not install packages or change host preferences or power settings.
