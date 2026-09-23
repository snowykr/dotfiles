#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT HUP INT TERM

mkdir -p "$root/zsh/.config/nvim" "$root/zsh/.config/ghostty" "$root/bash/.config/nvim" "$root/stubs"
printf 'previous zsh\n' > "$root/zsh/.zshrc"
printf 'local nvim\n' > "$root/zsh/.config/nvim/local.txt"
printf 'old ghostty\n' > "$root/zsh/.config/ghostty/config"
printf 'previous bash\n' > "$root/bash/.bashrc"

HOME="$root/zsh" SHELL=/bin/zsh "$repo/install.sh" --dry-run --no-packages > "$root/dry-run"
[ ! -e "$root/zsh/.dotfiles-backups" ]
[ ! -e "$root/zsh/.gitconfig" ]
[ ! -L "$root/zsh/.zshrc" ]
HOME="$root/zsh" SHELL=/bin/zsh "$repo/install.sh" --no-packages > "$root/installed"
[ "$(HOME="$root/zsh" git config --global --get user.name)" = snowykr ]
[ "$(HOME="$root/zsh" git config --global --get user.email)" = snowykr22@gmail.com ]
[ "$(readlink "$root/zsh/.zshrc")" = "$repo/shell/zshrc" ]
[ "$(readlink "$root/zsh/.config/nvim")" = "$repo/config/nvim" ]
if [ "$(uname -s)" = Darwin ]; then
    [ "$(readlink "$root/zsh/.config/ghostty/config")" = "$repo/config/ghostty/config" ]
else
    [ "$(cat "$root/zsh/.config/ghostty/config")" = 'old ghostty' ]
fi
set -- "$root/zsh"/.dotfiles-backups/*
[ "$#" -eq 1 ]
[ "$(cat "$1/.zshrc")" = 'previous zsh' ]
[ "$(cat "$1/.config/nvim/local.txt")" = 'local nvim' ]
if [ "$(uname -s)" = Darwin ]; then
    [ "$(cat "$1/.config/ghostty/config")" = 'old ghostty' ]
fi
HOME="$root/zsh" SHELL=/bin/zsh "$repo/install.sh" --no-packages > "$root/rerun"
set -- "$root/zsh"/.dotfiles-backups/*
[ "$#" -eq 1 ]

HOME="$root/bash" SHELL=/bin/bash "$repo/install.sh" --no-packages > "$root/bash-run"
[ "$(readlink "$root/bash/.bashrc")" = "$repo/shell/bashrc" ]
[ ! -e "$root/bash/.zshrc" ]
bash --noprofile -c '. "$1"; alias gmg >/dev/null; ! alias gm >/dev/null 2>&1' _ "$repo/shell/common.sh"
if command -v zsh >/dev/null 2>&1; then
    zsh -f -c 'source "$1"; alias gmg >/dev/null; ! alias gm >/dev/null 2>&1' _ "$repo/shell/common.sh"
fi
if HOME="$root/bash" SHELL=/bin/fish "$repo/install.sh" --no-packages > "$root/error" 2>&1; then
    printf 'Unknown shell should fail\n' >&2
    exit 1
fi

# Use a mock preference database so macOS writes never touch the host.
printf '#!/bin/sh\nprintf "Darwin\\n"\n' > "$root/stubs/uname"
printf '#!/bin/sh\nif [ "$1" = read ]; then\n    case "$2 $3" in\n        "-g AppleInterfaceStyle") echo Dark;;\n        "com.apple.dock autohide") echo 1;;\n        "com.apple.dock autohide-delay") echo 0;;\n        "com.apple.dock autohide-time-modifier") echo 0.5;;\n        "com.apple.dock tilesize") echo 20;;\n        "com.apple.dock show-recents") echo 0;;\n        "com.apple.finder ShowPathbar") echo 1;;\n        "-g AppleShowAllExtensions") echo 1;;\n    esac\nelse\n    printf "%%s\\n" "$*" >> "$TEST_LOG"\nfi\n' > "$root/stubs/defaults"
printf '#!/bin/sh\nprintf "restart %%s\\n" "$*" >> "$TEST_LOG"\n' > "$root/stubs/killall"
chmod +x "$root/stubs/uname" "$root/stubs/defaults" "$root/stubs/killall"
TEST_LOG="$root/preferences" PATH="$root/stubs:$PATH" "$repo/scripts/macos-defaults.sh" --dry-run > "$root/prefs-preview"
[ ! -e "$root/preferences" ]
TEST_LOG="$root/preferences" PATH="$root/stubs:$PATH" "$repo/scripts/macos-defaults.sh" > "$root/prefs-result"
[ "$(cat "$root/preferences")" = 'write com.apple.dock tilesize -int 44
restart Dock' ]

printf 'Install, backup, repeat-run and macOS preference tests passed.\n'
