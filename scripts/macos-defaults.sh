#!/bin/sh
set -eu

[ "$(uname -s)" = Darwin ] || { printf 'macOS only\n' >&2; exit 2; }
dry_run=0
if [ "${1:-}" = --dry-run ] && [ "$#" -eq 1 ]; then
    dry_run=1
elif [ "$#" -ne 0 ]; then
    printf 'Usage: %s [--dry-run]\n' "$0" >&2
    exit 2
fi

dock_changed=0
finder_changed=0
appearance_changed=0

ensure_pref() {
    domain=$1 key=$2 type=$3 desired=$4 service=$5
    current=$(defaults read "$domain" "$key" 2>/dev/null) || current='(unset)'
    expected=$desired
    case "$type:$desired" in
        bool:true) expected=1 ;;
        bool:false) expected=0 ;;
    esac
    [ "$current" = "$expected" ] && return
    printf '%s %s: %s -> %s\n' "$domain" "$key" "$current" "$desired"
    if [ "$dry_run" -eq 0 ]; then
        defaults write "$domain" "$key" "-$type" "$desired"
        case "$service" in
            Dock) dock_changed=1 ;;
            Finder) finder_changed=1 ;;
            appearance) appearance_changed=1 ;;
        esac
    fi
}

# Values captured from this Mac; do not reset Dock contents or input sources.
ensure_pref -g AppleInterfaceStyle string Dark appearance
ensure_pref com.apple.dock autohide bool true Dock
ensure_pref com.apple.dock autohide-delay float 0 Dock
ensure_pref com.apple.dock autohide-time-modifier float 0.5 Dock
ensure_pref com.apple.dock tilesize int 44 Dock
ensure_pref com.apple.dock show-recents bool false Dock
ensure_pref com.apple.finder ShowPathbar bool true Finder
ensure_pref -g AppleShowAllExtensions bool true Finder

if [ "$dry_run" -eq 0 ]; then
    [ "$dock_changed" -eq 0 ] || killall Dock
    [ "$finder_changed" -eq 0 ] || killall Finder
    if [ "$appearance_changed" -eq 1 ]; then
        printf 'Appearance may require logging out and back in to update every app.\n'
    fi
fi
