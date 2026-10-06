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
clock_changed=0
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
            ControlCenter) clock_changed=1 ;;
            appearance) appearance_changed=1 ;;
        esac
    fi
}

ensure_unset() {
    domain=$1 key=$2
    if defaults read "$domain" "$key" >/dev/null 2>&1; then
        printf '%s %s: remove override\n' "$domain" "$key"
        if [ "$dry_run" -eq 0 ]; then
            defaults delete "$domain" "$key"
            appearance_changed=1
        fi
    fi
}

# Disable idle system/display sleep for every power source.
# Locking can still explicitly turn off the display via loginwindow.
# Read before writing so repeat installs do not need sudo unnecessarily.
power_settings=$(pmset -g custom)
if ! printf '%s\n' "$power_settings" | awk '
    /^[[:space:]]*(Battery|AC|UPS) Power:/ { profile++; next }
    profile && ($1 == "sleep" || $1 == "displaysleep") {
        seen[profile, $1] = 1
        if ($2 != "0") changed = 1
    }
    END {
        for (i = 1; i <= profile; i++) {
            if (!seen[i, "sleep"] || !seen[i, "displaysleep"]) changed = 1
        }
        exit (profile == 0 || changed)
    }
'; then
    printf 'Power: disable automatic system and display sleep on all power sources\n'
    if [ "$dry_run" -eq 0 ]; then
        sudo pmset -a sleep 0 displaysleep 0
    fi
fi

# Preserve the current appearance: Dark with system defaults for other options.
ensure_pref -g AppleInterfaceStyle string Dark appearance
ensure_unset -g AppleInterfaceStyleSwitchesAutomatically
ensure_unset -g AppleAccentColor
ensure_unset -g AppleHighlightColor
ensure_unset -g AppleAquaColorVariant
ensure_unset -g AppleReduceDesktopTinting
ensure_unset -g AppleShowScrollBars
ensure_unset -g AppleScrollerPagingBehavior
ensure_unset -g AppleSidebarIconSize

# Use a digital, 24-hour menu bar clock with seconds; preserve date options.
ensure_pref com.apple.menuextra.clock IsAnalog bool false ControlCenter
ensure_pref com.apple.menuextra.clock Show24Hour bool true ControlCenter
ensure_pref com.apple.menuextra.clock ShowAMPM bool false ControlCenter
ensure_pref com.apple.menuextra.clock ShowSeconds bool true ControlCenter

# Do not reset Dock contents or input sources.
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
    [ "$clock_changed" -eq 0 ] || killall ControlCenter
    if [ "$appearance_changed" -eq 1 ]; then
        printf 'Appearance may require logging out and back in to update every app.\n'
    fi
fi
