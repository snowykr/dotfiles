#!/bin/sh
set -eu

[ "$#" -eq 0 ] || { [ "$#" -eq 1 ] && [ "$1" = --dry-run ]; } || {
    printf 'Usage: %s [--dry-run]\n' "$0" >&2
    exit 2
}
dry_run=0
[ "$#" -eq 0 ] || dry_run=1

if command -v starship >/dev/null 2>&1 && command -v eza >/dev/null 2>&1 && command -v gh >/dev/null 2>&1; then
    printf 'starship, eza and gh are already installed\n'
    exit 0
fi

case "$(uname -s)" in
    Darwin)
        command -v brew >/dev/null 2>&1 || {
            printf 'Homebrew is required: install it from https://brew.sh/\n' >&2
            exit 1
        }
        for package in starship eza gh; do
            if ! command -v "$package" >/dev/null 2>&1; then
                printf 'Install: brew install %s\n' "$package"
                [ "$dry_run" -eq 1 ] || brew install "$package"
            fi
        done ;;
    Linux)
        apt_packages=
        for package in eza gh; do
            if ! command -v "$package" >/dev/null 2>&1; then
                apt_packages="${apt_packages:+$apt_packages }$package"
            fi
        done
        if [ -n "$apt_packages" ]; then
            command -v apt-get >/dev/null 2>&1 || {
                printf 'eza and gh installation need apt-get on this Linux host\n' >&2
                exit 1
            }
            # The list consists only of the fixed package names above.
            set -- $apt_packages
            printf 'Install: sudo apt-get update && sudo apt-get install -y %s\n' "$apt_packages"
            if [ "$dry_run" -eq 0 ]; then
                sudo apt-get update
                sudo apt-get install -y "$@"
            fi
        fi
        if ! command -v starship >/dev/null 2>&1; then
            command -v curl >/dev/null 2>&1 || { printf 'curl is required for starship\n' >&2; exit 1; }
            printf 'Install: official starship installer to ~/.local/bin\n'
            if [ "$dry_run" -eq 0 ]; then
                installer=$(mktemp)
                trap 'rm -f "$installer"' EXIT HUP INT TERM
                curl -fsSL https://starship.rs/install.sh -o "$installer"
                mkdir -p "$HOME/.local/bin"
                sh "$installer" --bin-dir "$HOME/.local/bin" --yes
                rm -f "$installer"
                trap - EXIT HUP INT TERM
            fi
        fi ;;
    *) printf 'Unsupported OS\n' >&2; exit 2 ;;
esac
