# dotfiles

Personal shell, editor, terminal, and platform-aware macOS/Linux setup.

Two entrypoints have separate responsibilities:

- **`initialize.sh` configures the computer.** Run it on a new machine or to reapply installation changes.
- **`maintain.sh` keeps the installed checkout up to date.** It never runs initialization, installs packages, changes Git identity, applies macOS preferences, or invokes sudo.

## Initialize

This repository is private. Install [Homebrew](https://brew.sh/) and run `brew install gh` on macOS, or run `sudo apt-get update && sudo apt-get install -y gh` on Ubuntu.

```sh
gh auth login --hostname github.com --git-protocol https --web
gh auth setup-git
gh repo clone snowykr/dotfiles "$HOME/.dotfiles"
"$HOME/.dotfiles/initialize.sh" --dry-run
"$HOME/.dotfiles/initialize.sh"
```

Initialization detects the OS with `uname -s`, independently of the current login shell:

| Setting | macOS | Linux |
| --- | --- | --- |
| Shell configuration | `~/.zshrc` | `~/.bashrc` |
| Neovim configuration | Linked | Linked |
| Ghostty configuration | Linked | Unchanged |
| Appearance, clock, Dock, Finder | Applied | Skipped |
| System/display idle sleep | Disabled on all power sources | Unchanged |
| CLI installation | Homebrew | apt-get (Ubuntu/Debian) + official Starship installer |
| Automatic maintenance | User LaunchAgent | systemd user service and timer |

Missing CLI tools are installed: Neovim, ripgrep, fd, Starship, eza, gh, and lsof. Package names are mapped to executables (`neovim` → `nvim`, `ripgrep` → `rg`); Linux uses `fd-find` → `fdfind`. macOS zsh settings resolve the Homebrew prefix for Apple Silicon and Intel Macs.

Git identity is set to `snowykr` / `snowykr22@gmail.com`. Existing configuration is backed up under `~/.dotfiles-backups/` before linking. Repeated initialization leaves matching links and preferences unchanged. It does not change the login shell with `chsh`.

After successful initialization, automatic maintenance is registered for a `main` checkout with an `origin` remote. Registration is skipped on development branches. Private-repository credentials must work without a terminal prompt; authentication is not performed by a scheduled job.

Options:

- `--dry-run`: preview without changing files, preferences, Git configuration or scheduler registration.
- `--no-auto-update`: do not register automatic maintenance.
- `--no-packages`: skip CLI installation. On distributions without apt-get, install the listed tools manually and use this option.
- `--no-macos`: leave macOS appearance, clock, Dock, Finder and power settings unchanged.
- `--shell zsh|bash`: override the OS-selected shell configuration.
- `--homebrew`: additionally install macOS apps and fonts from `Brewfile`.

macOS preferences include Dark appearance, a digital 24-hour clock with seconds and no AM/PM label, an auto-hiding Dock, and Finder path/file-extension display. Clock date/day options are preserved. Clock changes restart ControlCenter.

Power setup uses `sudo pmset -a sleep 0 displaysleep 0` only when a power profile differs. This disables idle timers, **not** loginwindow's explicit display-off requests when locking. A dark screen does not prove that the system is asleep. Closing the lid, choosing Sleep or exhausting the battery can still suspend the Mac. Keeping the screen on increases battery use; connect power for long-running work. `caffeinate -di` can hold temporary display/system idle-sleep assertions when needed; initialization does not install an always-running caffeinate process.

To review or apply macOS preferences separately:

```sh
"$HOME/.dotfiles/scripts/macos-defaults.sh" --dry-run
"$HOME/.dotfiles/scripts/macos-defaults.sh"
```

## Maintain

```sh
"$HOME/.dotfiles/maintain.sh" update           # Update now
"$HOME/.dotfiles/maintain.sh" update --dry-run # Inspect eligibility without fetching
"$HOME/.dotfiles/maintain.sh" status           # Checkout, scheduling and recent results
"$HOME/.dotfiles/maintain.sh" enable           # Enable or refresh automatic maintenance
"$HOME/.dotfiles/maintain.sh" disable          # Disable automatic maintenance
```

`enable` and `disable` also accept `--dry-run`. `status` is read-only and uses the cached `origin/main`; it does not contact the remote. A dry-run update does not fetch or modify refs, logs or locks.

### Update safety

Updates operate on the actual installed repository path, not a hardcoded `~/.dotfiles` path. Only a clean `main` checkout can fast-forward to `origin/main`.

- Modified, staged or untracked files: skip without changing local work.
- Development branch, detached HEAD or an in-progress Git operation: skip.
- Local commits ahead of or diverged from upstream, including upstream rewrites: skip.
- Network/authentication failure: record an error and retry at the next scheduled run.
- Concurrent updates: only one obtains the update lock.
- Fetches are bounded by a 90-second watchdog. Branch, cleanliness and HEAD are checked again after fetching.

There is no automatic stash, reset, rebase or branch switch. Git hooks are disabled for maintenance operations. Use only a trusted `origin`: fetched shell and app configuration will be used when those programs next load it.

Logs and the update lock live outside the repository at `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles`. Update and macOS scheduler logs rotate at 64 KiB, keeping one previous file. If an updater is force-killed or the machine loses power, `status` can report a stale lock. Confirm no update is running before removing the reported `update.lock` directory; maintenance does not steal a lock from another process.

Keep machine-specific shell changes in `~/.zshrc.local` or `~/.bashrc.local` rather than editing the tracked files.

### Scheduling

- **macOS:** `com.snowykr.dotfiles.update` user LaunchAgent, every hour at minutes 00, 15, 30 and 45. Missed calendar events are coalesced after waking. No KeepAlive process or wake schedule is installed.
- **Linux:** `dotfiles-update.service` and `.timer` in the systemd user manager, every 15 minutes with `Persistent=true`. Missed calendar runs are caught up when the timer is activated. A working systemd user manager is required; unsupported systems fail explicitly rather than silently installing a different scheduler. User-manager lifetime determines whether it runs while logged out.

Both schedule `/bin/sh <installed-repo>/maintain.sh update`, without sudo. Absolute paths and an explicit PATH are registered because schedulers do not load `.zshrc` or `.bashrc`. `maintain.sh enable` refreshes definitions after scheduler-related changes.

### Receiving changes versus applying installation changes

| Remote change | Action |
| --- | --- |
| Existing aliases or shell configuration | Download automatically; open a new shell or source its config |
| Existing Neovim/Ghostty configuration | Download automatically; reload/restart the app as needed |
| New configuration links | Run `initialize.sh` again |
| New packages or apps | Run `initialize.sh` again |
| macOS system preferences | Run `initialize.sh` again |
| Scheduler definitions | Run `maintain.sh enable` again |

The maintenance command never calls initialization after updating. Updating linked files does not forcibly reload running shells or applications.

## Contents

- `initialize.sh` / `maintain.sh` — the two public entrypoints.
- `shell/` — zsh, bash and shared shell settings.
- `config/` — Ghostty and Neovim settings.
- `Brewfile` — macOS apps and CLI dependencies.
- `scripts/install-tools.sh` / `scripts/macos-defaults.sh` — initialization helpers.
- `scripts/scheduler.sh` — internal native scheduler backend.

## Test

```sh
sh scripts/test-initialize.sh
sh scripts/test-maintain.sh
sh scripts/test-scheduler.sh
sh scripts/test-install-tools.sh
```

Tests use temporary Git repositories and mock both operating systems, package managers, preference/power writes and scheduler commands. They do not install packages, register real jobs or change host preferences.
