#!/bin/sh
set -eu

[ "$#" -eq 0 ] || { [ "$#" -eq 1 ] && [ "$1" = --dry-run ]; } || {
    printf 'Usage: %s [--dry-run]\n' "$0" >&2
    exit 2
}
dry_run=0
[ "$#" -eq 0 ] || dry_run=1

# Include tools installed by this script even before the shell config is loaded.
export PATH="$HOME/.local/bin:$PATH"
os=$(uname -s)
case "$os" in
    Darwin|Linux) ;;
    *) printf 'Unsupported OS: %s\n' "$os" >&2; exit 2 ;;
esac

packages=
for tool in nvim rg fd starship eza gh lsof; do
    if command -v "$tool" >/dev/null 2>&1; then
        continue
    fi
    if [ "$tool" = fd ] && [ "$os" = Linux ] && command -v fdfind >/dev/null 2>&1; then
        continue
    fi
    case "$tool" in
        nvim) package=neovim ;;
        rg) package=ripgrep ;;
        fd) if [ "$os" = Linux ]; then package=fd-find; else package=fd; fi ;;
        starship) [ "$os" = Darwin ] || continue; package=starship ;;
        *) package=$tool ;;
    esac
    packages="${packages:+$packages }$package"
done

if [ "$os" = Linux ] && ! command -v starship >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
    packages="${packages:+$packages }curl"
fi

if [ -n "$packages" ]; then
    # The list consists only of the fixed package names above.
    set -- $packages
    case "$os" in
        Darwin)
            command -v brew >/dev/null 2>&1 || {
                printf 'Homebrew is required: install it from https://brew.sh/\n' >&2
                exit 1
            }
            for package in "$@"; do
                printf 'Install: brew install %s\n' "$package"
                [ "$dry_run" -eq 1 ] || brew install "$package"
            done ;;
        Linux)
            command -v apt-get >/dev/null 2>&1 || {
                printf 'Automatic Linux package installation requires apt-get (Ubuntu/Debian); install the CLI tools manually and use --no-packages on other distributions\n' >&2
                exit 1
            }
            printf 'Install: sudo apt-get update && sudo apt-get install -y %s\n' "$packages"
            if [ "$dry_run" -eq 0 ]; then
                sudo apt-get update
                sudo apt-get install -y "$@"
            fi ;;
    esac
fi

if [ "$os" = Linux ] && ! command -v starship >/dev/null 2>&1; then
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
elif [ -z "$packages" ]; then
    printf 'CLI tools are already installed\n'
fi
