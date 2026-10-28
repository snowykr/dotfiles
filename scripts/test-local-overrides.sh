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
shell_hook='[ -r "$HOME/.config/dotfiles/local/shell.sh" ] && . "$HOME/.config/dotfiles/local/shell.sh"'
[ "$(tail -n 1 "$repo/shell/zshrc")" = "$shell_hook" ] || fail 'shell/zshrc must end with the local override hook'
[ "$(tail -n 1 "$repo/shell/bashrc")" = "$shell_hook" ] || fail 'shell/bashrc must end with the local override hook'
[ "$(tail -n 1 "$repo/config/nvim/init.lua")" = 'require("config.local")' ] || fail 'config/nvim/init.lua must end by loading the local override module'
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
    HOME="$home" nvim --headless -u NONE \
        -c "lua package.path = '$repo/config/nvim/lua/?.lua;' .. package.path; require('config.local')" \
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

printf 'Local override hook, scaffold and preview tests passed.\n'
