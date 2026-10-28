# dotfiles

Personal shell, editor, terminal, and platform-aware macOS/Linux setup.

Two entrypoints have separate responsibilities:

- **`initialize.sh` configures the computer.** Run it on a new machine or to reapply installation changes.
- **`maintain.sh` keeps the installed checkout up to date.** It never runs initialization, installs packages, changes Git identity, applies macOS preferences, or invokes sudo. Its `local` subcommand only scaffolds the machine-local override files described below.

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

Updates operate on the actual installed repository path, not a hardcoded `~/.dotfiles` path. GitHub `origin/main` is the source of configuration; fast-forward eligibility requires a clean `main` checkout targeting it. Keep the installed checkout on `main` and do not switch branches while maintenance is running. Use a separate clone for development.

- Modified, staged or untracked files: skip without changing local work.
- Development branch, detached HEAD or an in-progress Git operation: skip.
- Local commits ahead of or diverged from upstream, including upstream rewrites: skip.
- Network/authentication failure: record an error and retry at the next scheduled run.
- Concurrent updates: only one obtains the update lock.
- Fetches are bounded by a 90-second watchdog. Branch, cleanliness and HEAD are checked again after fetching, but these checks do not atomically protect the checkout during the fast-forward.

The update lock serializes maintenance runs, **not interactive Git commands**. A reference-transaction guard checks the expected refs and that HEAD still names `main` when each transaction is prepared; this is not atomic checkout protection. Observed switches cause a skip or failure, not an automatic branch change. In the tested mid-merge independent-switch case, the switch succeeds and the guard rejects the final reference transaction, leaving both branch tips unchanged but downloaded changes staged in the index and present in the working tree. This residual state is an accepted failure outcome, not a clean-checkout guarantee: maintenance warns you to inspect the checkout manually and does not roll it back. Other interleavings can escape the checks, and there is no universal guarantee that refs or files remain unchanged. Disable scheduling and confirm no update is running before switching branches in the installed checkout.

Every update also re-verifies that the checkout is still `main` after a successful fast-forward. Below Git 2.28 the guard is unavailable, so maintenance skips the update in both real and preview runs instead of merging unguarded; upgrade Git, or fast-forward manually with `git -C <repo> pull --ff-only`. Interactive Git use in an installed checkout is still discouraged: use a separate clone for development and confirm no update is running before changing branches there.

There is no automatic stash, reset, rollback, rebase or branch switch. User Git hooks are disabled for maintenance operations; the fast-forward uses only the generated reference-transaction guard. This is not a sandbox. Use only a trusted `origin`: fetched shell and app configuration will be used when those programs next load it, and the fetched `maintain.sh` will execute unattended on the next scheduled run.

Logs and the update lock live outside the repository at `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles`. Update and macOS scheduler logs rotate at 64 KiB, keeping one previous file. If an updater is force-killed or the machine loses power, `status` can report a stale lock. Confirm no update is running before removing the reported `update.lock` directory; maintenance does not steal a lock from another process.

Keep machine-specific shell changes in `~/.config/dotfiles/local/shell.sh` rather than editing the tracked files; run `maintain.sh local` to create it (see Per-machine overrides).

The Neovim plugin lockfile is deliberately tracked source. `:Lazy update` (and install/clean operations that rewrite the lockfile) can modify it through the configuration symlink, so maintenance then pauses just as it does for any other local source change. Review and commit the intended lockfile changes through the repository workflow, or deliberately discard only those changes after review, before automatic checkout updates can resume. Unattended maintenance never discards plugin-lock changes; explicit `recover --discard-changes` discards them along with all other tracked edits.

### Explicit manual recovery

Unattended `update` never invokes recovery. When it stops, diagnostics list checkout changes and print a shell-quoted recovery command for the actual installed path and state directory. Review/back up those changes first, including any staged residue from a rejected mid-update race.

#### 1. Select the installed checkout and inspect it

Use the exact repository path printed by the update diagnostic, not a development clone. For installations in `~/.dotfiles-main`:

```sh
DOTFILES_REPO="$HOME/.dotfiles-main"
/bin/sh "$DOTFILES_REPO/maintain.sh" status
/bin/sh "$DOTFILES_REPO/maintain.sh" recover
```

For an installation in `~/.dotfiles`, change `DOTFILES_REPO` accordingly. If the diagnostic includes `XDG_STATE_HOME=...`, retain that same value for every command below so they share the scheduler's lock and logs. Plain `recover` only previews: it does **not** repair anything or fetch new history.

#### 2. Pause scheduling and back up work

Stop editors and interactive Git operations in this checkout. Inspect `status` and wait for any active maintenance to finish **before** disabling scheduling, especially on macOS: unloading the LaunchAgent can interrupt its running updater. If automatic maintenance is enabled, pause it once the active run has finished:

```sh
/bin/sh "$DOTFILES_REPO/maintain.sh" disable
/bin/sh "$DOTFILES_REPO/maintain.sh" status
```

On Linux, disabling the timer leaves an already-running update service running. On macOS, `launchctl bootout` unloads the job and may interrupt it. Disabling alone is **not proof that maintenance has finished**: recheck status, process/lock ownership, and checkout state before proceeding. If an update started between your checks, wait for it or inspect an interrupted run; do not remove an active lock to force recovery. Copy any work you need to keep **outside this checkout**, including staged edits, Neovim's tracked `lazy-lock.json`, and local commits. A full checkout backup including `.git` preserves more than a plain `git diff`, which does not include every kind of local work. Recovery makes no automatic backup.

#### 3. Preview, then explicitly discard

```sh
/bin/sh "$DOTFILES_REPO/maintain.sh" recover --discard-changes --dry-run
```

Read the affected paths, configured `origin`, and local-main commit list. The preview uses cached remote history; actual recovery fetches again and prints the updated commit-loss list before discarding. **The command below is destructive and does not ask for another interactive confirmation:**

```sh
/bin/sh "$DOTFILES_REPO/maintain.sh" recover --discard-changes
```

The `--discard-changes` flag is your acknowledgement. Never add this command to the automatic scheduler.

#### 4. Verify and resume

Successful recovery prints `Recovered: main -> <commit>`. Check the result:

```sh
git -C "$DOTFILES_REPO" branch --show-current  # main
git -C "$DOTFILES_REPO" status --short         # empty
/bin/sh "$DOTFILES_REPO/maintain.sh" status
```

If scheduling was enabled before you paused it, restore it only after verifying recovery:

```sh
/bin/sh "$DOTFILES_REPO/maintain.sh" enable
```

Open a new shell or reload/restart affected applications to use the recovered configuration.

#### Refusals and partial failures

| Message or condition | What to do |
| --- | --- |
| Untracked/ignored paths | Move the listed paths outside the checkout; even noncolliding files cause refusal. Do not delete them blindly. |
| Update lock exists | Wait for the running operation. For a stale lock, follow the ownership checks in **Update safety**; do not bypass an active lock. |
| Git operation in progress | Finish or deliberately abort that operation yourself after reviewing its changes. |
| Missing `main`, sparse checkout, or submodules | This recovery command does not support that checkout; inspect it manually. |
| Fetch/authentication/network failure | Fix connectivity or credentials; fetch failure occurs before tracked edits are discarded. |
| Failure after switching/reset starts | Some changes may already have been discarded and the branch may be `main`. Inspect status and your backup before retrying; there is no automatic rollback. |

#### Destructive scope and limits

**Recovery discards all tracked staged/working-tree edits and local `main` commits absent from freshly fetched `origin/main`.** It warns before mutation, fetches with the update watchdog, switches explicitly to the existing `main`, then resets only `main` to the verified fetched commit. It does not create/delete branches or reset a starting non-`main` branch tip; `main` is reset even when you started on `main`. Uncommitted tracked edits are discarded regardless of the starting branch. Fetch failure leaves your checkout work intact. Trust the configured `origin` before acknowledging: its configuration and scripts will replace yours.

Recovery shares the update lock and cleanup, disables user hooks, and guards reset reference transactions. It refuses in-progress Git operations, missing `main`, sparse checkouts, submodules, and **any untracked or ignored paths**, even noncolliding ones. Move those paths outside the checkout yourself first; recovery never runs `git clean`. Preview neither fetches nor writes refs, index, state, logs or locks; its commit list uses cached upstream history.

Stop editors and interactive Git operations before recovery. The maintenance lock does not exclude those processes; preflight checks and reference guards are not atomic worktree protection. Concurrent external writes/switches can still cause a partial failure, so do not race recovery. A refusal after switching may leave you on `main`; inspect rather than retrying blindly.

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

## Per-machine overrides

Machine-specific settings live outside the checkout, so updates never overwrite them and never have to be blocked to keep them:

```sh
"$HOME/.dotfiles/maintain.sh" local
"$HOME/.dotfiles/maintain.sh" local --dry-run
```

`local` creates `~/.config/dotfiles/local/` and fills in only the missing files; existing content is never rewritten, and `--dry-run` reports what it would create without writing. It never touches the checkout, never reads maintenance state, and never discards changes, so it also works on a dirty or out-of-date installation. The path is always `~/.config/dotfiles/local`, independent of `XDG_CONFIG_HOME`, because the Ghostty include cannot expand environment variables. A `~/.config/dotfiles/local` that is a symlink or a non-directory is refused rather than followed.

| File | Loaded by | Effect |
| --- | --- | --- |
| `shell.sh` | `shell/zshrc`, `shell/bashrc` | sourced last, after every dotfiles shell setting; both shells source it, so keep it POSIX `sh` |
| `nvim.lua` | `config/nvim/init.lua` via `config/local.lua` | run last in `init.lua`, after options, keymaps and the lazy.nvim plugin manager |
| `ghostty.conf` | `config/ghostty/config` (`config-file = ?~/.config/dotfiles/local/ghostty.conf`) | included after the directives above it |

Each hook is a file test, so a missing file is not an error and unused templates can be deleted. Because each runs last, later settings win: shell options, variables and aliases; Neovim `vim.opt`, `vim.keymap.set` and autocommands; Ghostty directives. Neovim plugins that load lazily can still change options after `nvim.lua` runs; confirm the effective value with `:verbose set` and use an `after/` plugin file for a setting a plugin keeps resetting. An error in `nvim.lua` surfaces at startup instead of being ignored.

Earlier versions of this repository sourced `$HOME/.zshrc.local` and `$HOME/.bashrc.local`; those files are no longer read. Merge their contents into `shell.sh` by hand if both exist, or copy them with:

```sh
mkdir -p "$HOME/.config/dotfiles/local"
for f in "$HOME/.zshrc.local" "$HOME/.bashrc.local"; do
    if [ -f "$f" ]; then cat "$f" >> "$HOME/.config/dotfiles/local/shell.sh"; fi
done
```

Editing the linked files under `~/.dotfiles` is not an override: it makes the checkout dirty and stops unattended updates. Change this repository for anything it should own, and keep machine-specific settings in these three files.

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
sh scripts/test-local-overrides.sh
nvim --headless -u NONE -l scripts/test-nvim.lua
```

Tests use temporary Git repositories and mock both operating systems, package managers, preference/power writes and scheduler commands. They do not install packages, register real jobs or change host preferences.
