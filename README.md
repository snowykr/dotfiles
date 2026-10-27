# dotfiles

Personal shell, editor, terminal, and platform-aware macOS/Linux setup.

Two entrypoints have separate responsibilities:

- **`initialize.sh` configures the computer.** Run it on a new machine or to reapply installation changes.
- **`maintain.sh` keeps the installed checkout up to date.** It never runs initialization, installs packages, changes Git identity, applies macOS preferences, or invokes sudo.

## Initialize

This repository is private. Install [Homebrew](https://brew.sh/) and run `brew install gh` on macOS, or run `sudo apt-get update && sudo apt-get install -y gh` on Ubuntu. Prepare the editor prerequisites listed below before running initialization.

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
| Tacit input method | Install/update latest via official installer | Skipped |
| Automatic maintenance (opt-in) | User LaunchAgent | systemd user service and timer |

The bundled editor configuration requires **Neovim 0.12 or newer**. On Linux, install a compatible [official Neovim build](https://github.com/neovim/neovim/releases) before initialization; distribution packages such as Ubuntu 24.04's Neovim 0.9.5 are too old. On macOS, missing Neovim is installed through Homebrew; upgrade an existing outdated installation first.

Editor setup also requires Node.js **22.22.2 or newer** with npm (for the current TypeScript language server), Go, a C compiler (`cc`), and [tree-sitter-cli](https://github.com/tree-sitter/tree-sitter/releases) 0.26.1 or newer for automatic language-server/parser installation. Download/extraction tools `curl`, `tar`, `unzip`, and `gzip` must also be available. Install these development prerequisites before initialization (on macOS, Homebrew provides `node`, `go`, and `tree-sitter-cli`; Apple's Command Line Tools provide `cc`). Tool preflight rejects missing or incompatible prerequisites instead of linking a known-broken editor setup. `--no-packages` skips tool installation/preflight and leaves these requirements to you.

Missing remaining CLI tools are installed: ripgrep, fd, Starship, eza, gh, and lsof. Package names are mapped to executables (`ripgrep` → `rg`); Linux uses `fd-find` → `fdfind`. Linux package availability is checked before the install batch; releases without a required package (for example, Ubuntu 22.04 without eza) require manually installing it or using a newer release. macOS zsh settings resolve the Homebrew prefix for Apple Silicon and Intel Macs.

On macOS, every explicit initialization installs or updates [Tacit](https://github.com/iamallyouneed/Tacit), even when it is already installed. The helper downloads the [official latest-release installer](https://github.com/iamallyouneed/tacit/releases/latest/download/install.sh) completely into a private temporary directory, then runs it with `/bin/sh` and cleans up. “Latest” is resolved at invocation, not pinned by this checkout. `--dry-run` neither downloads nor executes it; `--no-packages` opts out. `--no-macos` skips preferences only and **does not skip Tacit**. Maintenance never installs or updates Tacit.

This executes trusted upstream code: the installer chooses the platform package and checks its SHA-256; that checksum checks corruption, not independent authenticity. The upstream installer installs the unsigned app at `~/Library/Input Methods/tacit.app` and commands at `~/.local/bin/tacit` and `~/.local/bin/tacit-config`, removes quarantine attributes, and opens a welcome browser on first installation. Reruns retain the language edition and settings. **Log out and back in, then manually add Tacit as an input source in System Settings → Keyboard → Text Input → Edit.**

Git identity is set to `snowykr` / `snowykr22@gmail.com`. Application configuration is linked under `${XDG_CONFIG_HOME:-$HOME/.config}`; a custom configuration root must be absolute. Existing configuration is backed up under `~/.dotfiles-backups/` before linking. Repeated initialization leaves matching links and preferences unchanged. It does not change the login shell with `chsh`.

Automatic maintenance is **off by default on a fresh setup**. To opt in during initialization, run `./initialize.sh --auto-update`; after successful setup it registers maintenance for a `main` checkout with an `origin` remote. Registration is skipped on development branches. Plain initialization and its dry-run never change scheduler registration, including on repeat runs. To stop an already-enabled schedule, explicitly run `./maintain.sh disable`. Private-repository credentials must work without a terminal prompt; authentication is not performed by a scheduled job.

Options:

- `--dry-run`: preview without changing files, preferences, Git configuration or scheduler registration.
- `--auto-update`: opt in to automatic maintenance after successful setup. Omit it to leave existing scheduler state untouched.
- `--no-packages`: skip tool installation/preflight, including Tacit on macOS. On distributions without apt-get, install the listed tools manually and use this option.
- `--no-macos`: leave macOS appearance, clock, Dock, Finder and power settings unchanged; package installation, including Tacit, still runs.
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

Updates operate on the actual installed repository path, not a hardcoded `~/.dotfiles` path. Fast-forward eligibility requires a clean `main` checkout targeting `origin/main`.

- Modified, staged or untracked files: skip without changing local work.
- Development branch, detached HEAD or an in-progress Git operation: skip.
- Local commits ahead of or diverged from upstream, including upstream rewrites: skip.
- Network/authentication failure: record an error and retry at the next scheduled run.
- Concurrent updates: only one obtains the update lock.
- Fetches are bounded by a 90-second watchdog. Branch, cleanliness and HEAD are checked again after fetching, and the checkout and merged reference are bound to `main` while the fast-forward runs.

The update lock serializes maintenance runs, **not interactive Git commands**, so a branch switch can still overlap an update. The fast-forward is therefore bound to the checkout that was verified: a generated `reference-transaction` hook (Git 2.29 or newer) admits only the exact reference updates of this one fast-forward. A switch away from `main` before Git replaces files aborts the run with `Skipped: ... nothing was changed`; a switch after that point is refused as well, so **no branch other than `main` is ever advanced by maintenance**. In that rarer case the update is reported as a failure rather than a skip, because Git may already have replaced files: no branch was fast-forwarded and no local work was deleted, but inspect the checkout before continuing.

Every update also re-verifies that the checkout is still `main` after a successful fast-forward. Below Git 2.29 the guard is unavailable, so maintenance skips the update and asks for a manual `maintain.sh update` instead of merging unguarded. Interactive Git use in an installed checkout is still discouraged: use a separate clone for development and confirm no update is running before changing branches there.

There is no automatic stash, reset, rebase or branch switch. Git hooks are disabled for maintenance operations, but this is not a sandbox. Use only a trusted `origin`: fetched shell and app configuration will be used when those programs next load it, and the fetched `maintain.sh` will execute unattended on the next scheduled run.

Logs and the update lock live outside the repository at `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles`. Update and macOS scheduler logs rotate at 64 KiB, keeping one previous file. If an updater is force-killed or the machine loses power, `status` can report a stale lock. Confirm no update is running before removing the reported `update.lock` directory; maintenance does not steal a lock from another process.

Keep machine-specific shell changes in `~/.zshrc.local` or `~/.bashrc.local` rather than editing the tracked files.

The Neovim plugin lockfile is deliberately tracked source. `:Lazy update` (and install/clean operations that rewrite the lockfile) can modify it through the configuration symlink, so maintenance then pauses just as it does for any other local source change. Review and commit the intended lockfile changes through the repository workflow, or deliberately discard only those changes after review, before automatic checkout updates can resume. Maintenance never discards plugin-lock changes for you.

### Scheduling

- **macOS:** `com.snowykr.dotfiles.update` user LaunchAgent, every hour at minutes 00, 15, 30 and 45. Missed calendar events are coalesced after waking. No KeepAlive process or wake schedule is installed.
- **Linux:** `dotfiles-update.service` and `.timer` in the systemd user manager, every 15 minutes with `Persistent=true`. Missed calendar runs are caught up when the timer is activated. A reachable systemd user manager, `systemctl`, and `busctl` are required; unsupported systems fail explicitly rather than silently installing a different scheduler. User-manager lifetime determines whether it runs while logged out.

Linux keeps owned unit source files under the maintenance state directory's `systemd/` subdirectory. Registration uses the running manager's D-Bus unit-file methods to create persistent links in **that manager's** configuration directory, not the invoking shell's unit search path. A one-off caller `XDG_CONFIG_HOME` is preserved in the scheduled service environment without needing to match the manager's startup environment. Disable removes the timer registration and both manager links, without stopping an already-running update service. Disable the existing registration using its original state directory before changing `XDG_STATE_HOME`; conflicting unit names or foreign manager definitions are never overwritten.

Both schedule `/bin/sh <installed-repo>/maintain.sh update`, without sudo. Absolute paths and an explicit PATH are registered because schedulers do not load `.zshrc` or `.bashrc`. `maintain.sh enable` refreshes definitions after scheduler-related changes.

### Receiving changes versus applying installation changes

| Remote change | Action |
| --- | --- |
| Existing aliases or shell configuration | Download with `maintain.sh update`, or automatically when enabled; open a new shell or source its config |
| Existing Neovim/Ghostty configuration | Download with `maintain.sh update`, or automatically when enabled; reload/restart the app as needed |
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
nvim --headless -u NONE -l scripts/test-nvim.lua
```

Tests use temporary Git repositories and mock both operating systems, package managers, preference/power writes and scheduler commands. They do not install packages, register real jobs or change host preferences.
