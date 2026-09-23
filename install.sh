#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
mode=auto
dry_run=0
with_brew=0
with_macos=0
with_tools=1

usage() {
    printf 'Usage: %s [--dry-run] [--shell auto|zsh|bash] [--no-packages] [--homebrew] [--macos]\n' "$0"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run) dry_run=1 ;;
        --shell)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            mode=$2
            shift ;;
        --no-packages) with_tools=0 ;;
        --homebrew) with_brew=1 ;;
        --macos) with_macos=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
    shift
done

case "$mode" in
    auto)
        case "${SHELL:-}" in
            */zsh) mode=zsh ;;
            */bash) mode=bash ;;
            *) printf 'Unknown login shell: %s; use --shell zsh or --shell bash\n' "${SHELL:-unset}" >&2; exit 2 ;;
        esac ;;
    zsh|bash) ;;
    *) usage >&2; exit 2 ;;
esac

os=$(uname -s)
if [ "$with_brew" -eq 1 ] || [ "$with_macos" -eq 1 ]; then
    [ "$os" = Darwin ] || { printf 'Homebrew and macOS preferences require macOS\n' >&2; exit 2; }
fi

if [ "$with_tools" -eq 1 ]; then
    if [ "$dry_run" -eq 1 ]; then
        "$repo/scripts/install-tools.sh" --dry-run
    else
        "$repo/scripts/install-tools.sh"
    fi
fi

backup_dir="$HOME/.dotfiles-backups/$(date +%Y%m%d-%H%M%S)-$$"
backed_up=0

link_config() {
    source=$1
    destination=$2
    if [ -L "$destination" ] && [ "$(readlink "$destination")" = "$source" ]; then
        printf 'Already linked: %s\n' "$destination"
        return
    fi
    if [ -e "$destination" ] || [ -L "$destination" ]; then
        if [ "$backed_up" -eq 0 ]; then
            printf 'Backup directory: %s\n' "$backup_dir"
            if [ "$dry_run" -eq 0 ]; then mkdir -p "$backup_dir"; fi
            backed_up=1
        fi
        backup="$backup_dir/${destination#"$HOME"/}"
        printf 'Backup: %s -> %s\n' "$destination" "$backup"
        if [ "$dry_run" -eq 0 ]; then
            mkdir -p "$(dirname "$backup")"
            mv "$destination" "$backup"
        fi
    fi
    printf 'Link: %s -> %s\n' "$destination" "$source"
    if [ "$dry_run" -eq 0 ]; then
        mkdir -p "$(dirname "$destination")"
        ln -s "$source" "$destination"
    fi
}

case "$mode" in
    zsh) link_config "$repo/shell/zshrc" "$HOME/.zshrc" ;;
    bash) link_config "$repo/shell/bashrc" "$HOME/.bashrc" ;;
esac
link_config "$repo/config/nvim" "$HOME/.config/nvim"
if [ "$os" = Darwin ]; then
    link_config "$repo/config/ghostty/config" "$HOME/.config/ghostty/config"
fi

if [ "$with_brew" -eq 1 ]; then
    if ! command -v brew >/dev/null 2>&1; then
        printf 'Homebrew missing: install it from https://brew.sh/ before --homebrew\n' >&2
        exit 1
    fi
    if [ "$dry_run" -eq 1 ]; then
        printf 'Would run: brew bundle --file %s/Brewfile\n' "$repo"
    else
        brew bundle --file "$repo/Brewfile"
    fi
fi
if [ "$with_macos" -eq 1 ]; then
    if [ "$dry_run" -eq 1 ]; then
        "$repo/scripts/macos-defaults.sh" --dry-run
    else
        "$repo/scripts/macos-defaults.sh"
    fi
fi
