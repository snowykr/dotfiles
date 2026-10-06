#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT HUP INT TERM

# Mock both platforms, power settings and preference writes: never modify the host.
mkdir -p "$root/mac/.config/nvim" "$root/mac/.config/ghostty" "$root/linux/.config/nvim" "$root/linux/.config/ghostty" "$root/stubs"
printf '#!/bin/sh\nprintf "%%s\\n" "$MOCK_OS"\n' > "$root/stubs/uname"
printf '#!/bin/sh\nif [ "$1" = read ]; then\n    case "$2 $3" in\n        "-g AppleInterfaceStyle") if [ "${MOCK_APPLIED:-0}" = 1 ]; then echo Dark; else echo Light; fi;;\n        "-g AppleInterfaceStyleSwitchesAutomatically"|"-g AppleAccentColor"|"-g AppleHighlightColor"|"-g AppleReduceDesktopTinting")\n            [ "${MOCK_APPLIED:-0}" = 1 ] && exit 1\n            echo 1;;\n        "com.apple.menuextra.clock IsAnalog"|"com.apple.menuextra.clock ShowAMPM")\n            [ "${MOCK_CLOCK_UNSET:-0}" != 1 ] || exit 1\n            if [ "${MOCK_CLOCK_APPLIED:-${MOCK_APPLIED:-0}}" = 1 ]; then echo 0; else echo 1; fi;;\n        "com.apple.menuextra.clock Show24Hour"|"com.apple.menuextra.clock ShowSeconds")\n            [ "${MOCK_CLOCK_UNSET:-0}" != 1 ] || exit 1\n            if [ "${MOCK_CLOCK_APPLIED:-${MOCK_APPLIED:-0}}" = 1 ]; then echo 1; else echo 0; fi;;\n        "com.apple.dock autohide") echo 1;;\n        "com.apple.dock autohide-delay") echo 0;;\n        "com.apple.dock autohide-time-modifier") echo 0.5;;\n        "com.apple.dock tilesize") if [ "${MOCK_APPLIED:-0}" = 1 ]; then echo 44; else echo 20; fi;;\n        "com.apple.dock show-recents") echo 0;;\n        "com.apple.finder ShowPathbar") echo 1;;\n        "-g AppleShowAllExtensions") echo 1;;\n        *) exit 1;;\n    esac\nelse\n    printf "%%s\\n" "$*" >> "$TEST_LOG"\nfi\n' > "$root/stubs/defaults"
printf '#!/bin/sh\nprintf "restart %%s\\n" "$*" >> "$TEST_LOG"\n' > "$root/stubs/killall"
printf '#!/bin/sh\nprintf "brew %%s\\n" "$*" >> "$TEST_LOG"\n' > "$root/stubs/brew"
printf '%s\n' '#!/bin/sh
[ "$1 $2" = "-g custom" ] || exit 2
[ "${MOCK_PMSET_FAIL:-0}" = 0 ] || exit 1
timer=60
[ "${MOCK_POWER_APPLIED:-${MOCK_APPLIED:-0}}" != 1 ] || timer=0
if [ "${MOCK_POWER_PROFILE:-both}" != ac-only ]; then
    printf "Battery Power:\n sleep %s\n displaysleep %s\n disksleep 0\n" "${MOCK_BATTERY_SLEEP:-$timer}" "${MOCK_BATTERY_DISPLAY:-$timer}"
fi
printf "AC Power:\n sleep %s\n displaysleep %s\n disksleep 0\n" "${MOCK_AC_SLEEP:-$timer}" "${MOCK_AC_DISPLAY:-$timer}"
if [ "${MOCK_POWER_PROFILE:-both}" = ups ]; then
    printf "UPS Power:\n sleep %s\n displaysleep %s\n disksleep 0\n" "${MOCK_UPS_SLEEP:-$timer}" "${MOCK_UPS_DISPLAY:-$timer}"
fi
' > "$root/stubs/pmset"
printf '%s\n' '#!/bin/sh
printf "sudo %s\n" "$*" >> "$TEST_LOG"
[ "${MOCK_SUDO_FAIL:-0}" = 0 ]
' > "$root/stubs/sudo"
chmod +x "$root/stubs/uname" "$root/stubs/defaults" "$root/stubs/killall" "$root/stubs/brew" "$root/stubs/pmset" "$root/stubs/sudo"
PATH="$root/stubs:$PATH"
TEST_LOG="$root/preferences"
MOCK_OS=Darwin
export PATH TEST_LOG MOCK_OS

printf 'previous zsh\n' > "$root/mac/.zshrc"
printf 'local nvim\n' > "$root/mac/.config/nvim/local.txt"
printf 'old ghostty\n' > "$root/mac/.config/ghostty/config"
printf 'previous bash\n' > "$root/linux/.bashrc"
printf 'linux ghostty\n' > "$root/linux/.config/ghostty/config"

# OS defaults override the login shell; previews must not mutate anything.
HOME="$root/mac" SHELL=/bin/bash "$repo/initialize.sh" --dry-run --no-packages --no-auto-update > "$root/dry-run"
[ ! -e "$root/mac/.dotfiles-backups" ]
[ ! -e "$root/mac/.gitconfig" ]
[ ! -L "$root/mac/.zshrc" ]
[ ! -e "$root/preferences" ]
HOME="$root/mac" SHELL=/bin/bash "$repo/initialize.sh" --no-packages --no-auto-update > "$root/installed"
[ "$(HOME="$root/mac" git config --global --get user.name)" = snowykr ]
[ "$(HOME="$root/mac" git config --global --get user.email)" = snowykr22@gmail.com ]
[ "$(readlink "$root/mac/.zshrc")" = "$repo/shell/zshrc" ]
[ ! -e "$root/mac/.bashrc" ]
[ "$(readlink "$root/mac/.config/nvim")" = "$repo/config/nvim" ]
[ "$(readlink "$root/mac/.config/ghostty/config")" = "$repo/config/ghostty/config" ]
[ "$(cat "$root/preferences")" = 'sudo pmset -a sleep 0 displaysleep 0
write -g AppleInterfaceStyle -string Dark
delete -g AppleInterfaceStyleSwitchesAutomatically
delete -g AppleAccentColor
delete -g AppleHighlightColor
delete -g AppleReduceDesktopTinting
write com.apple.menuextra.clock IsAnalog -bool false
write com.apple.menuextra.clock Show24Hour -bool true
write com.apple.menuextra.clock ShowAMPM -bool false
write com.apple.menuextra.clock ShowSeconds -bool true
write com.apple.dock tilesize -int 44
restart Dock
restart ControlCenter' ]
set -- "$root/mac"/.dotfiles-backups/*
[ "$#" -eq 1 ]
[ "$(cat "$1/.zshrc")" = 'previous zsh' ]
[ "$(cat "$1/.config/nvim/local.txt")" = 'local nvim' ]
[ "$(cat "$1/.config/ghostty/config")" = 'old ghostty' ]
MOCK_APPLIED=1 TEST_LOG="$root/unchanged" HOME="$root/mac" SHELL=/bin/fish "$repo/initialize.sh" --no-packages --no-auto-update > "$root/rerun"
set -- "$root/mac"/.dotfiles-backups/*
[ "$#" -eq 1 ]
[ ! -e "$root/unchanged" ]

MOCK_OS=Linux TEST_LOG="$root/linux-preferences" HOME="$root/linux" SHELL=/bin/zsh "$repo/initialize.sh" --dry-run --no-packages --no-auto-update > "$root/linux-preview"
[ ! -L "$root/linux/.bashrc" ]
[ ! -e "$root/linux/.gitconfig" ]
MOCK_OS=Linux TEST_LOG="$root/linux-preferences" HOME="$root/linux" SHELL=/bin/zsh "$repo/initialize.sh" --no-packages --no-auto-update > "$root/linux-run"
[ "$(readlink "$root/linux/.bashrc")" = "$repo/shell/bashrc" ]
[ "$(readlink "$root/linux/.config/nvim")" = "$repo/config/nvim" ]
[ ! -e "$root/linux/.zshrc" ]
[ ! -e "$root/linux-preferences" ]
[ "$(cat "$root/linux/.config/ghostty/config")" = 'linux ghostty' ]
MOCK_OS=Linux HOME="$root/linux" SHELL= "$repo/initialize.sh" --no-packages --no-auto-update > "$root/linux-rerun"
set -- "$root/linux"/.dotfiles-backups/*
[ "$#" -eq 1 ]
[ "$(cat "$1/.bashrc")" = 'previous bash' ]

# Explicit shell selection and macOS opt-out remain available.
mkdir -p "$root/override" "$root/linux-zsh"
TEST_LOG="$root/opt-out-prefs" HOME="$root/override" "$repo/initialize.sh" --shell bash --no-macos --no-packages --no-auto-update > "$root/override-run"
[ "$(readlink "$root/override/.bashrc")" = "$repo/shell/bashrc" ]
[ ! -e "$root/override/.zshrc" ]
[ ! -e "$root/opt-out-prefs" ]
MOCK_OS=Linux HOME="$root/linux-zsh" "$repo/initialize.sh" --shell zsh --no-packages --no-auto-update > "$root/linux-zsh-run"
[ "$(readlink "$root/linux-zsh/.zshrc")" = "$repo/shell/zshrc" ]
TEST_LOG="$root/brew-preview-log" HOME="$root/apps" "$repo/initialize.sh" --homebrew --no-macos --dry-run --no-packages --no-auto-update > "$root/apps-preview"
[ ! -e "$root/brew-preview-log" ]
[ ! -e "$root/apps" ]
mkdir -p "$root/apps"
TEST_LOG="$root/brew-log" HOME="$root/apps" "$repo/initialize.sh" --homebrew --no-macos --no-packages --no-auto-update > "$root/apps-run"
[ "$(cat "$root/brew-log")" = "brew bundle --file $repo/Brewfile" ]

# Invalid requests and unsupported platforms fail before changing HOME.
if HOME="$root/invalid" "$repo/initialize.sh" --shell fish --no-packages --no-auto-update > "$root/error" 2>&1; then
    printf 'Invalid shell override should fail\n' >&2
    exit 1
fi
if MOCK_OS=FreeBSD HOME="$root/invalid" "$repo/initialize.sh" --no-packages --no-auto-update > "$root/error" 2>&1; then
    printf 'Unsupported OS should fail\n' >&2
    exit 1
fi
if MOCK_OS=Linux HOME="$root/invalid" "$repo/initialize.sh" --homebrew --no-packages --no-auto-update > "$root/error" 2>&1; then
    printf 'Homebrew apps on Linux should fail\n' >&2
    exit 1
fi
[ ! -e "$root/invalid" ]

bash --noprofile -c '. "$1"; alias gmg >/dev/null; ! alias gm >/dev/null 2>&1' _ "$repo/shell/common.sh"
if command -v zsh >/dev/null 2>&1; then
    zsh -f -c 'source "$1"; alias gmg >/dev/null; ! alias gm >/dev/null 2>&1' _ "$repo/shell/common.sh"

    # A nonstandard prefix proves Java and plugin paths come from brew --prefix.
    mkdir -p "$root/shell-home/.local/bin" "$root/brew-prefix/opt/openjdk/bin" "$root/brew-prefix/opt/openjdk/include" "$root/brew-prefix/share/zsh-autosuggestions" "$root/brew-prefix/share/zsh-syntax-highlighting"
    ln -s "$repo/shell/zshrc" "$root/shell-home/.zshrc"
    printf '#!/bin/sh\n[ "$1" = --prefix ] || exit 1\nprintf "%%s\\n" "$TEST_BREW_PREFIX"\n' > "$root/shell-home/.local/bin/brew"
    # Prevent host-installed prompt/version managers from running in this test.
    for tool in starship pyenv rbenv; do
        printf '#!/bin/sh\nexit 0\n' > "$root/shell-home/.local/bin/$tool"
        chmod +x "$root/shell-home/.local/bin/$tool"
    done
    chmod +x "$root/shell-home/.local/bin/brew"
    printf 'DOTFILES_AUTOSUGGESTIONS_LOADED=1\n' > "$root/brew-prefix/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
    printf 'DOTFILES_HIGHLIGHTING_LOADED=1\n' > "$root/brew-prefix/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
    HOME="$root/shell-home" TEST_BREW_PREFIX="$root/brew-prefix" zsh -dfi -c '
        OSTYPE=darwin
        source "$HOME/.zshrc"
        [[ "$path[1]" == "$TEST_BREW_PREFIX/opt/openjdk/bin" ]] || exit 1
        [[ "$CPPFLAGS" == "-I$TEST_BREW_PREFIX/opt/openjdk/include" ]] || exit 1
        [[ "$DOTFILES_AUTOSUGGESTIONS_LOADED" == 1 && "$DOTFILES_HIGHLIGHTING_LOADED" == 1 ]] || exit 1
        alias gmg >/dev/null
    '
    HOME="$root/shell-home" TEST_BREW_PREFIX="$root/brew-prefix" zsh -dfi -c '
        OSTYPE=linux-gnu
        source "$HOME/.zshrc"
        [[ -z "${DOTFILES_AUTOSUGGESTIONS_LOADED:-}${DOTFILES_HIGHLIGHTING_LOADED:-}" ]] || exit 1
        alias gmg >/dev/null
    '
fi

# Power-only changes need sudo; previews and already configured profiles do not.
MOCK_APPLIED=1 MOCK_POWER_APPLIED=0 TEST_LOG="$root/power-preview-log" "$repo/scripts/macos-defaults.sh" --dry-run > "$root/power-preview"
[ ! -e "$root/power-preview-log" ]
[ "$(cat "$root/power-preview")" = 'Power: disable automatic system and display sleep on all power sources' ]
MOCK_APPLIED=1 MOCK_POWER_APPLIED=0 TEST_LOG="$root/power-log" "$repo/scripts/macos-defaults.sh" > "$root/power-result"
[ "$(cat "$root/power-log")" = 'sudo pmset -a sleep 0 displaysleep 0' ]

# Check each setting and power source independently, even if all others are zero.
for setting in MOCK_BATTERY_SLEEP MOCK_BATTERY_DISPLAY MOCK_AC_SLEEP MOCK_AC_DISPLAY; do
    env MOCK_APPLIED=1 "$setting=60" TEST_LOG="$root/$setting-log" "$repo/scripts/macos-defaults.sh" > "$root/$setting-result"
    [ "$(cat "$root/$setting-log")" = 'sudo pmset -a sleep 0 displaysleep 0' ]
done
MOCK_APPLIED=1 MOCK_POWER_PROFILE=ac-only TEST_LOG="$root/ac-only-log" "$repo/scripts/macos-defaults.sh" > "$root/ac-only-result"
[ ! -e "$root/ac-only-log" ]
MOCK_APPLIED=1 MOCK_POWER_PROFILE=ac-only MOCK_AC_DISPLAY=60 TEST_LOG="$root/ac-display-log" "$repo/scripts/macos-defaults.sh" > "$root/ac-display-result"
[ "$(cat "$root/ac-display-log")" = 'sudo pmset -a sleep 0 displaysleep 0' ]
MOCK_APPLIED=1 MOCK_POWER_PROFILE=ups MOCK_UPS_SLEEP=60 TEST_LOG="$root/ups-log" "$repo/scripts/macos-defaults.sh" > "$root/ups-result"
[ "$(cat "$root/ups-log")" = 'sudo pmset -a sleep 0 displaysleep 0' ]
MOCK_APPLIED=1 TEST_LOG="$root/power-unchanged-log" "$repo/scripts/macos-defaults.sh" > "$root/power-unchanged-result"
[ ! -e "$root/power-unchanged-log" ]

# Failure to read or apply power settings must stop, not silently skip the policy.
if MOCK_PMSET_FAIL=1 TEST_LOG="$root/power-read-fail-log" "$repo/scripts/macos-defaults.sh" > "$root/power-read-error" 2>&1; then
    printf 'Power read failure should fail\n' >&2
    exit 1
fi
[ ! -e "$root/power-read-fail-log" ]
if MOCK_SUDO_FAIL=1 TEST_LOG="$root/power-write-fail-log" "$repo/scripts/macos-defaults.sh" > "$root/power-write-error" 2>&1; then
    printf 'Power write failure should fail\n' >&2
    exit 1
fi
[ "$(cat "$root/power-write-fail-log")" = 'sudo pmset -a sleep 0 displaysleep 0' ]

# Clock-only changes refresh ControlCenter, without restarting Dock or Finder.
MOCK_APPLIED=1 MOCK_CLOCK_APPLIED=0 TEST_LOG="$root/clock-preview-log" "$repo/scripts/macos-defaults.sh" --dry-run > "$root/clock-preview"
[ ! -e "$root/clock-preview-log" ]
[ "$(cat "$root/clock-preview")" = 'com.apple.menuextra.clock IsAnalog: 1 -> false
com.apple.menuextra.clock Show24Hour: 0 -> true
com.apple.menuextra.clock ShowAMPM: 1 -> false
com.apple.menuextra.clock ShowSeconds: 0 -> true' ]
MOCK_APPLIED=1 MOCK_CLOCK_APPLIED=0 TEST_LOG="$root/clock-log" "$repo/scripts/macos-defaults.sh" > "$root/clock-result"
[ "$(cat "$root/clock-log")" = 'write com.apple.menuextra.clock IsAnalog -bool false
write com.apple.menuextra.clock Show24Hour -bool true
write com.apple.menuextra.clock ShowAMPM -bool false
write com.apple.menuextra.clock ShowSeconds -bool true
restart ControlCenter' ]
# Missing keys must be written as well; applied settings produce no writes.
MOCK_APPLIED=1 MOCK_CLOCK_UNSET=1 TEST_LOG="$root/clock-unset-log" "$repo/scripts/macos-defaults.sh" > "$root/clock-unset-result"
[ "$(cat "$root/clock-unset-log")" = "$(cat "$root/clock-log")" ]
MOCK_APPLIED=1 TEST_LOG="$root/clock-unchanged-log" "$repo/scripts/macos-defaults.sh" > "$root/clock-unchanged-result"
[ ! -e "$root/clock-unchanged-log" ]

TEST_LOG="$root/prefs-preview-log" "$repo/scripts/macos-defaults.sh" --dry-run > "$root/prefs-preview"
[ ! -e "$root/prefs-preview-log" ]
if MOCK_OS=Linux "$repo/scripts/macos-defaults.sh" > "$root/error" 2>&1; then
    printf 'Standalone macOS preferences on Linux should fail\n' >&2
    exit 1
fi
# Initialization delegates registration only after successful setup.
fixture="$root/registration repo"
mkdir -p "$fixture/shell" "$fixture/config/nvim" "$fixture/config/ghostty" "$root/registration-home"
cp "$repo/initialize.sh" "$fixture/initialize.sh"
printf '%s\n' '#!/bin/sh
printf "maintain %s\n" "$*" >> "$REGISTRATION_LOG"
' > "$fixture/maintain.sh"
REGISTRATION_LOG="$root/registration-log" HOME="$root/registration-home" "$fixture/initialize.sh" --no-packages --no-macos > "$root/registration-result"
[ "$(cat "$root/registration-log")" = 'maintain enable' ]
REGISTRATION_LOG="$root/registration-preview-log" HOME="$root/registration-home" "$fixture/initialize.sh" --no-packages --no-macos --dry-run > "$root/registration-preview"
[ "$(cat "$root/registration-preview-log")" = 'maintain enable --dry-run' ]
REGISTRATION_LOG="$root/registration-disabled-log" HOME="$root/registration-home" "$fixture/initialize.sh" --no-packages --no-macos --no-auto-update > "$root/registration-disabled"
[ ! -e "$root/registration-disabled-log" ]
if MOCK_OS=FreeBSD REGISTRATION_LOG="$root/registration-failed-log" HOME="$root/registration-home" "$fixture/initialize.sh" --no-packages --no-macos > "$root/registration-error" 2>&1; then
    printf 'Unsupported initialization should fail\n' >&2
    exit 1
fi
[ ! -e "$root/registration-failed-log" ]
printf 'Initialization, backup, preferences and maintenance registration tests passed.\n'
