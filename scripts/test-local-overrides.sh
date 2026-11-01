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
    # A distro login banner may precede the marker, so only the final line is ours.
    printf 'DOTFILES_LOCAL_MARKER=from-local\n' > "$home/.config/dotfiles/local/shell.sh"
    output=$(HOME="$home" "$shell" -i -c 'printf "%s\\n" "${DOTFILES_LOCAL_MARKER:-missing}"' 2>/dev/null) ||
        fail "$shell failed to load the dotfiles configuration"
    marker=$(printf '%s\n' "$output" | tail -n 1)
    [ "$marker" = 'from-local' ] || fail "$shell did not load the local override (got: $output)"
    rm "$home/.config/dotfiles/local/shell.sh"
    output=$(HOME="$home" "$shell" -i -c 'printf "%s\\n" "${DOTFILES_LOCAL_MARKER:-missing}"' 2>/dev/null) ||
        fail "$shell failed when the local override was absent"
    marker=$(printf '%s\n' "$output" | tail -n 1)
    [ "$marker" = 'missing' ] || fail "$shell did not tolerate a missing local override (got: $output)"
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

# Reject physical destinations inside the checkout, not just a symlink at local/.
# Use a disposable script checkout so a regression cannot write into this repo.
boundary_repo="$root/boundary/checkout"
mkdir -p "$boundary_repo"
cp "$repo/maintain.sh" "$boundary_repo/maintain.sh"

assert_boundary_refused() {
    boundary_home=$1
    for preview in preview real; do
        set --
        [ "$preview" != preview ] || set -- --dry-run
        if HOME="$boundary_home" /bin/sh "$boundary_repo/maintain.sh" local "$@" > "$root/boundary.out" 2>&1; then
            fail "maintain.sh local accepted an unsafe path ($boundary_home; $preview)"
        fi
        grep -q 'must be outside the repository' "$root/boundary.out" ||
            fail "maintain.sh local did not explain the checkout boundary: $(cat "$root/boundary.out")"
    done
}

config_link_home="$root/config-link-home"
mkdir -p "$config_link_home"
ln -s "$boundary_repo" "$config_link_home/.config"
assert_boundary_refused "$config_link_home"
[ ! -e "$boundary_repo/dotfiles" ] || fail 'local created directories through a linked .config'

dotfiles_link_home="$root/dotfiles-link-home"
mkdir -p "$dotfiles_link_home/.config"
ln -s "$boundary_repo" "$dotfiles_link_home/.config/dotfiles"
assert_boundary_refused "$dotfiles_link_home"
[ ! -e "$boundary_repo/local" ] || fail 'local created directories through a linked dotfiles parent'

# The same rejection applies when the destination already exists, without edits.
mkdir -p "$boundary_repo/dotfiles/local"
printf 'keep my override\n' > "$boundary_repo/dotfiles/local/shell.sh"
assert_boundary_refused "$config_link_home"
[ "$(cat "$boundary_repo/dotfiles/local/shell.sh")" = 'keep my override' ] ||
    fail 'local modified an existing override inside the checkout'
[ ! -e "$boundary_repo/dotfiles/local/nvim.lua" ] || fail 'local filled a template inside the checkout'
[ ! -e "$boundary_repo/dotfiles/local/ghostty.conf" ] || fail 'local filled a template inside the checkout'

# A physical destination equal to the checkout must be rejected too.
exact_repo="$root/exact/local"
exact_home="$root/exact-home"
mkdir -p "$exact_repo" "$exact_home/.config"
cp "$repo/maintain.sh" "$exact_repo/maintain.sh"
ln -s "$root/exact" "$exact_home/.config/dotfiles"
for preview in preview real; do
    set --
    [ "$preview" != preview ] || set -- --dry-run
    if HOME="$exact_home" /bin/sh "$exact_repo/maintain.sh" local "$@" > "$root/exact.out" 2>&1; then
        fail "maintain.sh local accepted the checkout root ($preview)"
    fi
    grep -q 'must be outside the repository' "$root/exact.out" || fail 'local did not explain the exact boundary'
done
[ ! -e "$exact_repo/shell.sh" ] || fail 'local wrote templates at the checkout root'

# HOME itself can be inside the checkout even without any symlinks.
assert_boundary_refused "$boundary_repo/home"
[ ! -e "$boundary_repo/home" ] || fail 'local created HOME inside the checkout'

# Benign ancestor symlinks outside the checkout remain supported, including a
# sibling sharing the checkout prefix. Preview must not create missing suffixes.
safe_home="$root/safe-link-home"
safe_target="$boundary_repo-sibling"
mkdir -p "$safe_home" "$safe_target"
ln -s "$safe_target" "$safe_home/.config"
HOME="$safe_home" /bin/sh "$boundary_repo/maintain.sh" local --dry-run > "$root/safe-preview.out" ||
    fail 'local rejected a safe ancestor symlink during preview'
[ ! -e "$safe_target/dotfiles" ] || fail 'local preview created directories through a safe symlink'
HOME="$safe_home" /bin/sh "$boundary_repo/maintain.sh" local > "$root/safe.out" ||
    fail 'local rejected a safe ancestor symlink'
for entry in shell.sh nvim.lua ghostty.conf; do
    [ -f "$safe_target/dotfiles/local/$entry" ] || fail "local did not create $entry through a safe symlink"
done

# Parent traversal must be refused before lexical normalization hides a symlink.
traversal_home="$root/missing/../config-link-home"
for preview in preview real; do
    set --
    [ "$preview" != preview ] || set -- --dry-run
    if HOME="$traversal_home" /bin/sh "$boundary_repo/maintain.sh" local "$@" > "$root/local-traversal.out" 2>&1; then
        fail "local accepted HOME parent traversal ($preview)"
    fi
    grep -q 'parent traversal' "$root/local-traversal.out" || fail 'local did not explain the traversal refusal'
done
[ ! -e "$root/missing" ] || fail 'local created an ancestor before rejecting traversal'

# Invalid HOME and unusable ancestors fail clearly without creating anything.
newline='
'
carriage_return=$(printf '\r')
for invalid in relative dangling blocked newline carriage physical-newline physical-trailing-newline physical-carriage; do
    invalid_home="$root/invalid-$invalid"
    case "$invalid" in
        relative) invalid_home=relative-home; expected='must be an absolute path' ;;
        dangling)
            mkdir -p "$invalid_home"
            ln -s "$root/nonexistent-target" "$invalid_home/.config"
            expected='is not a directory' ;;
        blocked)
            mkdir -p "$invalid_home"
            printf 'keep this file\n' > "$invalid_home/.config"
            expected='is not a directory' ;;
        newline) invalid_home="$root/invalid${newline}home"; expected='newline and carriage-return' ;;
        carriage) invalid_home="$root/invalid${carriage_return}home"; expected='newline and carriage-return' ;;
        physical-*)
            case "$invalid" in
                physical-newline) invalid_target="$root/target${newline}suffix" ;;
                physical-trailing-newline) invalid_target="$root/target$newline" ;;
                physical-carriage) invalid_target="$root/target${carriage_return}suffix" ;;
            esac
            mkdir -p "$invalid_home" "$invalid_target"
            ln -s "$invalid_target" "$invalid_home/.config"
            expected='newline and carriage-return' ;;
    esac
    for preview in preview real; do
        set --
        [ "$preview" != preview ] || set -- --dry-run
        if HOME="$invalid_home" /bin/sh "$boundary_repo/maintain.sh" local "$@" > "$root/invalid-path.out" 2>&1; then
            fail "local accepted an invalid $invalid path ($preview)"
        fi
        grep -q "$expected" "$root/invalid-path.out" ||
            fail "local did not explain the invalid $invalid path: $(cat "$root/invalid-path.out")"
    done
    case "$invalid" in
        newline|carriage) [ ! -e "$invalid_home" ] || fail 'local created an invalid HOME' ;;
        physical-*) [ ! -e "$invalid_target/dotfiles" ] || fail 'local wrote through an invalid physical ancestor' ;;
    esac
done
[ ! -e "$root/nonexistent-target" ] || fail 'local created a dangling symlink destination'
[ "$(cat "$root/invalid-blocked/.config")" = 'keep this file' ] || fail 'local modified a blocking ancestor'

# A newline in the physical checkout path must survive pwd capture until refusal,
# even when the invocation path itself has no newline (an ancestor symlink).
newline_repo="$root/repo$newline"
mkdir -p "$newline_repo"
cp "$repo/maintain.sh" "$newline_repo/maintain.sh"
ln -s "$newline_repo" "$root/repo-alias"
for script in "$newline_repo/maintain.sh" "$root/repo-alias/maintain.sh"; do
    if HOME="$root/script-home" /bin/sh "$script" local > "$root/repo-path.out" 2>&1; then
        fail 'local accepted a newline-containing repository path'
    fi
    grep -q 'newline and carriage-return' "$root/repo-path.out" ||
        fail 'local did not explain the invalid repository path'
done
[ ! -e "$root/script-home" ] || fail 'local wrote before validating the repository path'

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
