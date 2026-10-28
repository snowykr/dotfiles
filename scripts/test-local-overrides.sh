#!/bin/sh
set -eu
unset GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS XDG_CONFIG_HOME XDG_STATE_HOME
unset DOTFILES_LOCAL_MARKER
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_NOSYSTEM
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
root=$(mktemp -d)
root=$(CDPATH= cd -- "$root" && pwd -P)
trap 'rm -rf "$root"' EXIT HUP INT TERM

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

# Each hook must be the last thing its managed configuration does, so an override wins.
shell_hook='if [ -f "$HOME/.config/dotfiles/local/shell.sh" ]; then
    . "$HOME/.config/dotfiles/local/shell.sh"
fi'
[ "$(tail -n 3 "$repo/shell/zshrc")" = "$shell_hook" ] || fail 'shell/zshrc must end with the local override hook'
[ "$(tail -n 3 "$repo/shell/bashrc")" = "$shell_hook" ] || fail 'shell/bashrc must end with the local override hook'
[ "$(tail -n 1 "$repo/config/nvim/init.lua")" = 'require("config.local")' ] || fail 'config/nvim/init.lua must end by loading the local override module'
# Ending with it is not enough: it must run after the plugin manager registers plugins.
lazy_line=$(grep -n 'require("config.lazy")' "$repo/config/nvim/init.lua" | tail -n 1 | cut -d: -f1)
local_line=$(grep -n 'require("config.local")' "$repo/config/nvim/init.lua" | tail -n 1 | cut -d: -f1)
[ -n "$lazy_line" ] && [ -n "$local_line" ] && [ "$local_line" -gt "$lazy_line" ] ||
    fail 'config/nvim/init.lua must load the local override after config.lazy'
[ "$(tail -n 1 "$repo/config/ghostty/config")" = 'config-file = ?~/.config/dotfiles/local/ghostty.conf' ] || fail 'config/ghostty/config must end with the local include'

# The shell hooks only run through the linked entrypoints that source common.sh.
home="$root/home"
mkdir -p "$home/.config/dotfiles/local"
ln -s "$repo/shell/zshrc" "$home/.zshrc"
ln -s "$repo/shell/bashrc" "$home/.bashrc"

check_shell() {
    shell=$1
    if ! command -v "$shell" > /dev/null 2>&1; then
        printf 'Skipped: %s is not installed\n' "$shell"
        return 0
    fi
    printf 'DOTFILES_LOCAL_MARKER=from-local\n' > "$home/.config/dotfiles/local/shell.sh"
    output=$(HOME="$home" "$shell" -i -c 'printf %s "${DOTFILES_LOCAL_MARKER:-missing}"' 2>/dev/null) ||
        fail "$shell failed to load the dotfiles configuration"
    [ "$output" = 'from-local' ] || fail "$shell did not load the local override (got: $output)"
    rm "$home/.config/dotfiles/local/shell.sh"
    output=$(HOME="$home" "$shell" -i -c 'printf %s "${DOTFILES_LOCAL_MARKER:-missing}"' 2>/dev/null) ||
        fail "$shell failed when the local override was absent"
    [ "$output" = 'missing' ] || fail "$shell did not tolerate a missing local override (got: $output)"
}
check_shell zsh
check_shell bash

# Neovim loads the override module directly, without plugins or network access.
nvim_local="$home/.config/dotfiles/local/nvim.lua"
run_nvim_local() {
    HOME="$home" DOTFILES_REPO="$repo" nvim --headless -u NONE \
        -c "lua package.path = vim.env.DOTFILES_REPO .. '/config/nvim/lua/?.lua;' .. package.path; require('config.local')" \
        -c 'lua io.stdout:write(tostring(vim.g.dotfiles_local_marker))' \
        -c 'quitall!' 2>&1
}
printf 'vim.g.dotfiles_local_marker = "from-local"\n' > "$nvim_local"
output=$(run_nvim_local) || fail "nvim failed to load the local override: $output"
case $output in
    *from-local*) ;;
    *) fail "nvim did not load the local override (got: $output)" ;;
esac
rm "$nvim_local"
output=$(run_nvim_local) || fail "nvim failed when the local override was absent: $output"
case $output in
    *nil*) ;;
    *) fail "nvim did not tolerate a missing local override (got: $output)" ;;
esac

# Running the real init.lua must reach the override after the plugin manager, so a
# stub config.lazy stands in for the bootstrap that would clone lazy.nvim.
nvim_stub="$root/nvimstub"
mkdir -p "$nvim_stub/config"
printf '%s\n' "vim.g.dotfiles_local_order = (vim.g.dotfiles_local_order or '') .. 'lazy'" > "$nvim_stub/config/lazy.lua"
printf '%s\n' \
    'package.path = vim.env.DOTFILES_STUB .. "/?.lua;" .. vim.env.DOTFILES_REPO .. "/config/nvim/lua/?.lua;" .. package.path' \
    'dofile(vim.env.DOTFILES_REPO .. "/config/nvim/init.lua")' \
    'io.stdout:write(tostring(vim.g.dotfiles_local_order))' \
    'vim.cmd("quitall!")' > "$nvim_stub/order.lua"
printf '%s\n' "vim.g.dotfiles_local_order = (vim.g.dotfiles_local_order or '') .. 'local'" > "$nvim_local"
output=$(HOME="$home" DOTFILES_STUB="$nvim_stub" DOTFILES_REPO="$repo" \
    nvim --headless -u "$nvim_stub/order.lua" 2>&1) ||
    fail "nvim failed while loading init.lua with a local override: $output"
case $output in
    *lazylocal*) ;;
    *) fail "init.lua did not load the local override after config.lazy (got: $output)" ;;
esac
rm "$nvim_local"

# maintain.sh local creates the templates, never clobbers, and previews without writing.
scaffold_home="$root/scaffold"
mkdir -p "$scaffold_home"
HOME="$scaffold_home" /bin/sh "$repo/maintain.sh" local > "$root/scaffold.out" ||
    fail 'maintain.sh local failed on an empty home'
for entry in shell.sh nvim.lua ghostty.conf; do
    [ -f "$scaffold_home/.config/dotfiles/local/$entry" ] || fail "maintain.sh local did not create $entry"
done
grep -q '^Created: ' "$root/scaffold.out" || fail 'maintain.sh local did not report created files'
printf 'alias mine=1\n' > "$scaffold_home/.config/dotfiles/local/shell.sh"
HOME="$scaffold_home" /bin/sh "$repo/maintain.sh" local > "$root/scaffold-again.out" ||
    fail 'maintain.sh local failed on an existing home'
[ "$(cat "$scaffold_home/.config/dotfiles/local/shell.sh")" = 'alias mine=1' ] ||
    fail 'maintain.sh local overwrote an existing override'
grep -q '^Kept existing: ' "$root/scaffold-again.out" || fail 'maintain.sh local did not report kept files'

preview_home="$root/preview"
mkdir -p "$preview_home"
HOME="$preview_home" /bin/sh "$repo/maintain.sh" local --dry-run > "$root/preview.out" ||
    fail 'maintain.sh local --dry-run failed'
[ ! -e "$preview_home/.config/dotfiles/local" ] || fail 'maintain.sh local --dry-run created the override directory'
grep -q '^Would create: ' "$root/preview.out" || fail 'maintain.sh local --dry-run did not preview the files'

blocked_home="$root/blocked"
mkdir -p "$blocked_home/.config/dotfiles"
printf 'not a directory\n' > "$blocked_home/.config/dotfiles/local"
if HOME="$blocked_home" /bin/sh "$repo/maintain.sh" local > "$root/blocked.out" 2>&1; then
    fail 'maintain.sh local should refuse a non-directory override path'
fi
grep -q '^Refused: ' "$root/blocked.out" || fail 'maintain.sh local did not explain the refusal'
[ "$(cat "$blocked_home/.config/dotfiles/local")" = 'not a directory' ] || fail 'maintain.sh local modified the blocking file'

# A symlinked override directory could redirect the writes into the checkout.
linked_home="$root/linked"
mkdir -p "$linked_home/.config/dotfiles"
ln -s "$repo" "$linked_home/.config/dotfiles/local"
if HOME="$linked_home" /bin/sh "$repo/maintain.sh" local > "$root/linked.out" 2>&1; then
    fail 'maintain.sh local should refuse a symlinked override directory'
fi
grep -q '^Refused: ' "$root/linked.out" || fail 'maintain.sh local did not explain the symlink refusal'
[ -L "$linked_home/.config/dotfiles/local" ] || fail 'maintain.sh local replaced the symlinked override directory'
[ ! -e "$repo/shell.sh" ] || fail 'maintain.sh local wrote into the checkout through a symlink'

# local never reads maintenance state, so it must work with an unusable state path.
relstate_home="$root/relstate"
mkdir -p "$relstate_home"
HOME="$relstate_home" XDG_STATE_HOME="relative/state" /bin/sh "$repo/maintain.sh" local > "$root/relstate.out" 2>&1 ||
    fail "maintain.sh local failed with a relative XDG_STATE_HOME: $(cat "$root/relstate.out")"
[ -f "$relstate_home/.config/dotfiles/local/shell.sh" ] ||
    fail 'maintain.sh local did not create templates with a relative XDG_STATE_HOME'

# `local` must never be able to reach destructive recovery.
if HOME="$scaffold_home" /bin/sh "$repo/maintain.sh" local --discard-changes > "$root/discard.out" 2>&1; then
    fail 'maintain.sh local must reject --discard-changes'
fi
grep -q '^Usage: ' "$root/discard.out" || fail 'maintain.sh local --discard-changes did not print usage'

# An unset HOME must report itself instead of aborting on an unbound variable.
if env -u HOME /bin/sh "$repo/maintain.sh" local > "$root/nohome.out" 2>&1; then
    fail 'maintain.sh local must fail when HOME is unset'
fi
grep -q 'HOME is not set' "$root/nohome.out" ||
    fail "maintain.sh local did not report the missing HOME: $(cat "$root/nohome.out")"

# A real create failure must report the underlying reason, not a generic message.
if [ "$(id -u)" -ne 0 ]; then
    readonly_home="$root/readonly"
    mkdir -p "$readonly_home/.config/dotfiles/local"
    chmod 500 "$readonly_home/.config/dotfiles/local"
    if HOME="$readonly_home" /bin/sh "$repo/maintain.sh" local > "$root/readonly.out" 2>&1; then
        fail 'maintain.sh local should fail when the override directory is not writable'
    fi
    chmod 700 "$readonly_home/.config/dotfiles/local"
    grep -q '^Failed: could not create .*: .' "$root/readonly.out" ||
        fail "maintain.sh local discarded the create failure reason: $(cat "$root/readonly.out")"
    if grep -q 'never updates or overwrites' "$root/readonly.out"; then
        fail 'maintain.sh local reported success guidance after a create failure'
    fi
fi

printf 'Local override hook, scaffold and preview tests passed.\n'
