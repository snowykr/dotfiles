#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT HUP INT TERM
mkdir -p "$root/bin" "$root/home"
for tool in mktemp rm mkdir sh cp; do
    ln -s "$(command -v "$tool")" "$root/bin/$tool"
done

printf '#!/bin/sh\nprintf "Darwin\\n"\n' > "$root/bin/uname"
printf '#!/bin/sh\nprintf "brew %%s\\n" "$*" >> "$TEST_LOG"\n' > "$root/bin/brew"
chmod +x "$root/bin/uname" "$root/bin/brew"
HOME="$root/home" TEST_LOG="$root/log" PATH="$root/bin" "$repo/scripts/install-tools.sh" --dry-run > "$root/preview"
[ ! -e "$root/log" ]
HOME="$root/home" TEST_LOG="$root/log" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/mac-output"
[ "$(cat "$root/log")" = 'brew install starship
brew install eza
brew install gh' ]

printf '#!/bin/sh\nprintf "Linux\\n"\n' > "$root/bin/uname"
printf '#!/bin/sh\nexit 0\n' > "$root/bin/apt-get"
printf '#!/bin/sh\nprintf "sudo %%s\\n" "$*" >> "$TEST_LOG"\n' > "$root/bin/sudo"
printf '#!/bin/sh\nmkdir -p "$HOME/.local/bin"\nprintf ready > "$HOME/.local/bin/starship"\n' > "$root/installer"
printf '#!/bin/sh\nwhile [ "$#" -gt 0 ]; do\n    if [ "$1" = -o ]; then shift; output=$1; fi\n    shift\ndone\ncp "$MOCK_INSTALLER" "$output"\n' > "$root/bin/curl"
chmod +x "$root/bin/uname" "$root/bin/apt-get" "$root/bin/sudo" "$root/bin/curl"
: > "$root/log"
HOME="$root/home" TEST_LOG="$root/log" MOCK_INSTALLER="$root/installer" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/linux-output"
[ "$(cat "$root/log")" = 'sudo apt-get update
sudo apt-get install -y eza gh' ]
[ "$(cat "$root/home/.local/bin/starship")" = ready ]
printf 'Mocked macOS and Linux package installations passed.\n'
