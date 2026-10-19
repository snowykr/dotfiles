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
printf '#!/bin/sh\nprintf "NVIM v%%s\\n" "$MOCK_NVIM_VERSION"\n' > "$root/nvim-tool"
printf '#!/bin/sh\nexit 0\n' > "$root/tool"
chmod +x "$root/tool"
printf '#!/bin/sh\nprintf "tree-sitter %%s\\n" "$MOCK_TREE_SITTER_VERSION"\n' > "$root/bin/tree-sitter"
printf '#!/bin/sh\nprintf "v%%s\\n" "$MOCK_NODE_VERSION"\n' > "$root/bin/node"
for tool in npm go cc tar unzip gzip curl; do
    cp "$root/tool" "$root/bin/$tool"
done
printf '#!/bin/sh\nprintf "brew %%s\\n" "$*" >> "$TEST_LOG"\ncase "$2" in\n    neovim) cp "$MOCK_NVIM" "$MOCK_BIN/nvim";;\n    ripgrep) tool=rg;;\n    *) tool=$2;;\nesac\n[ "$2" = neovim ] || cp "$MOCK_TOOL" "$MOCK_BIN/$tool"\n' > "$root/bin/brew"
printf '#!/bin/sh\nprintf "sudo %%s\\n" "$*" >> "$TEST_LOG"\ncase "$2" in\n    update) : > "$APT_UPDATE_MARKER"; exit 0;;\n    install) ;;\n    *) exit 0;;\nesac\nshift 3\nfor package in "$@"; do\n    case "$package" in\n        ripgrep) tool=rg;; fd-find) tool=fdfind;;\n        curl) cp "$MOCK_CURL" "$MOCK_BIN/curl"; continue;;\n        *) tool=$package;;\n    esac\n    cp "$MOCK_TOOL" "$MOCK_BIN/$tool"\ndone\n' > "$root/bin/sudo"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$APT_CACHE_LOG"\n[ -e "$APT_UPDATE_MARKER" ] || exit 1\nif [ "$2" = "$MOCK_NO_CANDIDATE" ]; then\n    exit 0\nelse\n    printf "Candidate: 1.0\\n"\nfi\n' > "$root/bin/apt-cache"
printf '#!/bin/sh\nexit 0\n' > "$root/bin/apt-get"
printf '#!/bin/sh\nmkdir -p "$HOME/.local/bin"\ncp "$MOCK_TOOL" "$HOME/.local/bin/starship"\n' > "$root/installer"
printf '#!/bin/sh\nwhile [ "$#" -gt 0 ]; do\n    if [ "$1" = -o ]; then shift; output=$1; fi\n    shift\ndone\ncp "$MOCK_INSTALLER" "$output"\n' > "$root/curl"
chmod +x "$root/bin/uname" "$root/bin/tree-sitter" "$root/bin/node" "$root/bin/brew" "$root/bin/sudo" "$root/bin/apt-cache" "$root/bin/apt-get" "$root/nvim-tool" "$root/tool" "$root/installer" "$root/curl"

TEST_LOG="$root/log"
APT_CACHE_LOG="$root/apt-cache-log"
APT_UPDATE_MARKER="$root/apt-update-ready"
MOCK_BIN="$root/bin"
MOCK_TOOL="$root/tool"
MOCK_NVIM="$root/nvim-tool"
MOCK_NVIM_VERSION=0.12.0
MOCK_NODE_VERSION=22.22.2
MOCK_TREE_SITTER_VERSION=0.26.1
MOCK_OS=Darwin
MOCK_INSTALLER="$root/installer"
MOCK_CURL="$root/curl"
MOCK_NO_CANDIDATE=
export TEST_LOG APT_CACHE_LOG APT_UPDATE_MARKER MOCK_BIN MOCK_TOOL MOCK_NVIM
export MOCK_NVIM_VERSION MOCK_NODE_VERSION MOCK_TREE_SITTER_VERSION MOCK_OS MOCK_INSTALLER MOCK_CURL MOCK_NO_CANDIDATE

# Dry-run previews Homebrew installs without creating tools.
HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" --dry-run > "$root/preview"
[ ! -e "$root/log" ]
[ ! -e "$root/bin/nvim" ]
MOCK_NODE_VERSION=22.22.1
export MOCK_NODE_VERSION
if TEST_LOG="$root/old-node-log" HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" --dry-run > "$root/error" 2>&1; then
    printf 'Node.js below 22.22.2 should fail preflight\n' >&2
    exit 1
fi
case "$(cat "$root/error")" in *'Node.js 22.22.2 or newer is required'*) ;; *) exit 1 ;; esac
[ ! -e "$root/old-node-log" ]
MOCK_NODE_VERSION=22.22.2-rc.1
export MOCK_NODE_VERSION
if TEST_LOG="$root/node-prerelease-log" HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" --dry-run > "$root/error" 2>&1; then
    printf 'Node.js 22.22.2 prerelease should fail preflight\n' >&2
    exit 1
fi
[ ! -e "$root/node-prerelease-log" ]
MOCK_NODE_VERSION=22.22.2
export MOCK_NODE_VERSION
HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/mac-output"
[ "$(cat "$root/log")" = 'brew install neovim
brew install ripgrep
brew install fd
brew install starship
brew install eza
brew install gh
brew install lsof' ]
# New installations are checked after Homebrew completes; existing old nvim is rejected before package actions.
MOCK_NVIM_VERSION=0.11.5
export MOCK_NVIM_VERSION
if TEST_LOG="$root/mac-old-log" HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/error" 2>&1; then
    printf 'Outdated existing Neovim should fail\n' >&2
    exit 1
fi
[ ! -e "$root/mac-old-log" ]
rm "$root/bin/nvim"
: > "$root/log"
if HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/error" 2>&1; then
    printf 'Outdated newly installed Neovim should fail\n' >&2
    exit 1
fi
[ "$(cat "$root/log")" = 'brew install neovim' ]
MOCK_NVIM_VERSION=0.12.0
export MOCK_NVIM_VERSION
cp "$root/nvim-tool" "$root/bin/nvim"
TEST_LOG="$root/mac-rerun-log" HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/mac-rerun"
[ ! -e "$root/mac-rerun-log" ]
rm "$root/bin/nvim" "$root/bin/rg" "$root/bin/fd" "$root/bin/starship" "$root/bin/eza" "$root/bin/gh" "$root/bin/lsof" "$root/bin/curl"

MOCK_OS=Linux
export MOCK_OS
# Missing or outdated Linux Neovim is rejected before apt update/install, including dry-run.
if TEST_LOG="$root/linux-missing-nvim-log" HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" --dry-run > "$root/error" 2>&1; then
    printf 'Missing Linux Neovim should fail before package installation\n' >&2
    exit 1
fi
[ ! -e "$root/linux-missing-nvim-log" ]
[ ! -e "$root/apt-update-ready" ]
printf '#!/bin/sh\nprintf "NVIM v%%s\\n" "$MOCK_NVIM_VERSION"\n' > "$root/old-nvim"
chmod +x "$root/old-nvim"
MOCK_NVIM_VERSION=0.11.5
export MOCK_NVIM_VERSION
cp "$root/old-nvim" "$root/bin/nvim"
if TEST_LOG="$root/linux-old-nvim-log" HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" --dry-run > "$root/error" 2>&1; then
    printf 'Outdated Linux Neovim should fail before package installation\n' >&2
    exit 1
fi
[ ! -e "$root/linux-old-nvim-log" ]
MOCK_NVIM_VERSION=0.12.0
export MOCK_NVIM_VERSION
cp "$root/nvim-tool" "$root/bin/nvim"

# A dry-run does not call apt; the real run updates metadata, checks all candidates, then installs one batch.
TEST_LOG="$root/linux-preview-log" HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" --dry-run > "$root/linux-preview"
[ ! -e "$root/linux-preview-log" ]
[ ! -e "$root/home/.local/bin/starship" ]
[ ! -e "$root/bin/curl" ]
: > "$root/log"
rm -f "$root/apt-update-ready" "$root/apt-cache-log"
HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/linux-output"
[ "$(cat "$root/log")" = 'sudo apt-get update
sudo apt-get install -y ripgrep fd-find eza gh lsof curl' ]
[ -x "$root/home/.local/bin/starship" ]
[ -x "$root/bin/fdfind" ]
[ ! -e "$root/bin/fd" ]
# fdfind and ~/.local/bin/starship count as installed on repeat runs.
TEST_LOG="$root/linux-rerun-log" HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/linux-rerun"
[ ! -e "$root/linux-rerun-log" ]

# Missing prerequisites fail clearly before package operations.
rm "$root/bin/go"
if TEST_LOG="$root/missing-prereq-log" HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/error" 2>&1; then
    printf 'Missing Go prerequisite should fail\n' >&2
    exit 1
fi
case "$(cat "$root/error")" in *'Missing required editor setup prerequisite: go'*) ;; *) exit 1 ;; esac
[ ! -e "$root/missing-prereq-log" ]
cp "$root/tool" "$root/bin/go"
rm "$root/bin/unzip"
if TEST_LOG="$root/missing-archive-tool-log" HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/error" 2>&1; then
    printf 'Missing unzip prerequisite should fail\n' >&2
    exit 1
fi
case "$(cat "$root/error")" in *'Missing required editor setup prerequisite: unzip'*) ;; *) exit 1 ;; esac
[ ! -e "$root/missing-archive-tool-log" ]
cp "$root/tool" "$root/bin/unzip"

MOCK_TREE_SITTER_VERSION=0.26.0
export MOCK_TREE_SITTER_VERSION
if TEST_LOG="$root/old-tree-sitter-log" HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/error" 2>&1; then
    printf 'Outdated tree-sitter-cli should fail preflight\n' >&2
    exit 1
fi
case "$(cat "$root/error")" in *'tree-sitter-cli 0.26.1 or newer is required'*) ;; *) exit 1 ;; esac
[ ! -e "$root/old-tree-sitter-log" ]
MOCK_TREE_SITTER_VERSION=0.26.1
export MOCK_TREE_SITTER_VERSION

# An unavailable apt candidate aborts before the installation batch.
rm "$root/bin/eza"
MOCK_NO_CANDIDATE=eza
export MOCK_NO_CANDIDATE
: > "$root/log"
rm -f "$root/apt-update-ready" "$root/apt-cache-log"
if HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/error" 2>&1; then
    printf 'Unavailable apt candidate should fail before install\n' >&2
    exit 1
fi
[ "$(cat "$root/log")" = 'sudo apt-get update' ]
[ "$(cat "$root/apt-cache-log")" = 'policy eza' ]
MOCK_NO_CANDIDATE=
export MOCK_NO_CANDIDATE
cp "$root/tool" "$root/bin/eza"

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
export MOCK_OS
rm "$root/bin/brew"
if TEST_LOG="$root/no-brew-log" HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/error" 2>&1; then
    printf 'Missing Homebrew should fail\n' >&2
    exit 1
fi
[ ! -e "$root/no-brew-log" ]
printf 'Mocked macOS/Linux mappings, Neovim/prerequisite/apt preflights, previews and repeat-run tests passed.\n'
