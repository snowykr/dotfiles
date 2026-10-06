#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT HUP INT TERM
mkdir -p "$root/bin" "$root/home"
for tool in mktemp rm mkdir sh cp chmod; do
    ln -s "$(command -v "$tool")" "$root/bin/$tool"
done

printf '#!/bin/sh\nprintf "%%s\\n" "$MOCK_OS"\n' > "$root/bin/uname"
# Model newly installed executables as well as recording package-manager calls.
printf '#!/bin/sh\nprintf "brew %%s\\n" "$*" >> "$TEST_LOG"\ncase "$2" in\n    neovim) tool=nvim;; ripgrep) tool=rg;; *) tool=$2;;\nesac\ncp "$MOCK_TOOL" "$MOCK_BIN/$tool"\n' > "$root/bin/brew"
printf '#!/bin/sh\nexit 0\n' > "$root/tool"
chmod +x "$root/bin/uname" "$root/bin/brew" "$root/tool"
TEST_LOG="$root/log"
MOCK_BIN="$root/bin"
MOCK_TOOL="$root/tool"
MOCK_OS=Darwin
export TEST_LOG MOCK_BIN MOCK_TOOL MOCK_OS
HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" --dry-run > "$root/preview"
[ ! -e "$root/log" ]
[ ! -e "$root/bin/nvim" ]
HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/mac-output"
[ "$(cat "$root/log")" = 'brew install neovim
brew install ripgrep
brew install fd
brew install starship
brew install eza
brew install gh
brew install lsof' ]
TEST_LOG="$root/mac-rerun-log" HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/mac-rerun"
[ ! -e "$root/mac-rerun-log" ]
rm "$root/bin/nvim" "$root/bin/rg" "$root/bin/fd" "$root/bin/starship" "$root/bin/eza" "$root/bin/gh" "$root/bin/lsof"

MOCK_OS=Linux
printf '#!/bin/sh\nexit 0\n' > "$root/bin/apt-get"
printf '#!/bin/sh\nprintf "sudo %%s\\n" "$*" >> "$TEST_LOG"\n[ "$2" = install ] || exit 0\nshift 3\nfor package in "$@"; do\n    case "$package" in\n        neovim) tool=nvim;; ripgrep) tool=rg;; fd-find) tool=fdfind;;\n        curl) cp "$MOCK_CURL" "$MOCK_BIN/curl"; continue;;\n        *) tool=$package;;\n    esac\n    cp "$MOCK_TOOL" "$MOCK_BIN/$tool"\ndone\n' > "$root/bin/sudo"
printf '#!/bin/sh\nmkdir -p "$HOME/.local/bin"\ncp "$MOCK_TOOL" "$HOME/.local/bin/starship"\n' > "$root/installer"
printf '#!/bin/sh\nwhile [ "$#" -gt 0 ]; do\n    if [ "$1" = -o ]; then shift; output=$1; fi\n    shift\ndone\ncp "$MOCK_INSTALLER" "$output"\n' > "$root/curl"
chmod +x "$root/bin/apt-get" "$root/bin/sudo" "$root/curl"
MOCK_INSTALLER="$root/installer"
MOCK_CURL="$root/curl"
export MOCK_INSTALLER MOCK_CURL
TEST_LOG="$root/linux-preview-log" HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" --dry-run > "$root/linux-preview"
[ ! -e "$root/linux-preview-log" ]
[ ! -e "$root/home/.local/bin/starship" ]
[ ! -e "$root/bin/curl" ]
: > "$root/log"
HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/linux-output"
[ "$(cat "$root/log")" = 'sudo apt-get update
sudo apt-get install -y neovim ripgrep fd-find eza gh lsof curl' ]
[ -x "$root/home/.local/bin/starship" ]
[ -x "$root/bin/fdfind" ]
[ ! -e "$root/bin/fd" ]
# fdfind and ~/.local/bin/starship count as installed on repeat runs.
TEST_LOG="$root/linux-rerun-log" HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/linux-rerun"
[ ! -e "$root/linux-rerun-log" ]

# A single missing executable only installs its matching package.
rm "$root/bin/rg"
TEST_LOG="$root/partial-log" HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/partial-output"
[ "$(cat "$root/partial-log")" = 'sudo apt-get update
sudo apt-get install -y ripgrep' ]

if MOCK_OS=FreeBSD HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/error" 2>&1; then
    printf 'Unsupported OS should fail even with all tools installed\n' >&2
    exit 1
fi
rm "$root/bin/rg" "$root/bin/apt-get"
if TEST_LOG="$root/unsupported-log" HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/error" 2>&1; then
    printf 'Missing apt-get should fail\n' >&2
    exit 1
fi
[ ! -e "$root/unsupported-log" ]
MOCK_OS=Darwin
rm "$root/bin/brew"
if TEST_LOG="$root/no-brew-log" HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/error" 2>&1; then
    printf 'Missing Homebrew should fail\n' >&2
    exit 1
fi
[ ! -e "$root/no-brew-log" ]
printf 'Mocked macOS/Linux package mappings, previews and repeat-run tests passed.\n'
