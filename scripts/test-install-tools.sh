#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT HUP INT TERM
mkdir -p "$root/bin" "$root/home"
for tool in mktemp rm mkdir sh cp chmod dirname; do
    ln -s "$(command -v "$tool")" "$root/bin/$tool"
done

printf '#!/bin/sh\nprintf "%%s\\n" "$MOCK_OS"\n' > "$root/bin/uname"
printf '#!/bin/sh\nprintf "NVIM v%%s\\n" "$MOCK_NVIM_VERSION"\n' > "$root/nvim-tool"
printf '#!/bin/sh\nexit 0\n' > "$root/tool"
chmod +x "$root/tool"
printf '#!/bin/sh\nprintf "tree-sitter %%s\\n" "$MOCK_TREE_SITTER_VERSION"\n' > "$root/bin/tree-sitter"
printf '#!/bin/sh\nprintf "v%%s\\n" "$MOCK_NODE_VERSION"\n' > "$root/bin/node"
for tool in npm go tar unzip gzip; do
    cp "$root/tool" "$root/bin/$tool"
done
cat > "$root/compiler" <<'COMPILER'
#!/bin/sh
set -eu
[ "$#" -eq 3 ] && [ "$2" = -o ]
source_file=$1
output_file=$3
[ -f "$source_file" ]
stdint=0
stdlib=0
while IFS= read -r line; do
    case "$line" in
        "#include <stdint.h>") stdint=1 ;;
        "#include <stdlib.h>") stdlib=1 ;;
    esac
done < "$source_file"
[ "$stdint$stdlib" = 11 ]
printf "%s\n" "${0##*/}" > "$COMPILER_LOG"
printf "%s\n" "$source_file" "$output_file" > "$COMPILER_PATH_LOG"
# Create partial output on failure so cleanup covers linker/compiler leftovers.
printf "#!/bin/sh\nprintf executed >> \"\$COMPILER_EXEC_LOG\"\nexit 99\n" > "$output_file"
case "${MOCK_COMPILER_FAILURE:-}" in
    headers) printf "fatal error: stdint.h: No such file or directory\n" >&2; exit 1 ;;
    linker) printf "ld: cannot find Scrt1.o\n" >&2; exit 1 ;;
    no-output) rm "$output_file"; exit 0 ;;
    empty-output) : > "$output_file"; exit 0 ;;
    noexec-output) chmod 0644 "$output_file"; exit 0 ;;
esac
chmod +x "$output_file"
COMPILER
chmod +x "$root/compiler"
cp "$root/compiler" "$root/bin/cc"
printf '#!/bin/sh\n[ "${HOMEBREW_NO_ASK:-}" = 1 ] || exit 91\nprintf "brew %%s\\n" "$*" >> "$TEST_LOG"\n[ "$2" != "${MOCK_SKIP_PACKAGE:-}" ] || exit 0\ncase "$2" in\n    neovim) cp "$MOCK_NVIM" "$MOCK_BIN/nvim";;\n    ripgrep) tool=rg;;\n    *) tool=$2;;\nesac\n[ "$2" = neovim ] || cp "$MOCK_TOOL" "$MOCK_BIN/$tool"\n' > "$root/bin/brew"
printf '#!/bin/sh\nprintf "sudo %%s\\n" "$*" >> "$TEST_LOG"\ncase "$2" in\n    update) : > "$APT_UPDATE_MARKER"; exit 0;;\n    install) ;;\n    *) exit 0;;\nesac\nshift 3\nfor package in "$@"; do\n    [ "$package" != "${MOCK_SKIP_PACKAGE:-}" ] || continue\n    case "$package" in\n        ripgrep) tool=rg;; fd-find) tool=fdfind;;\n        curl) cp "$MOCK_CURL" "$MOCK_BIN/curl"; continue;;\n        *) tool=$package;;\n    esac\n    cp "$MOCK_TOOL" "$MOCK_BIN/$tool"\ndone\n' > "$root/bin/sudo"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$APT_CACHE_LOG"\n[ -e "$APT_UPDATE_MARKER" ] || exit 1\nif [ "$2" = "$MOCK_NO_CANDIDATE" ]; then\n    exit 0\nelse\n    printf "Candidate: 1.0\\n"\nfi\n' > "$root/bin/apt-cache"
printf '#!/bin/sh\nexit 0\n' > "$root/bin/apt-get"
printf '#!/bin/sh\n[ "${MOCK_SKIP_STARSHIP:-0}" = 0 ] || exit 0\nmkdir -p "$HOME/.local/bin"\ncp "$MOCK_TOOL" "$HOME/.local/bin/starship"\n' > "$root/installer"
cat > "$root/tacit-installer" <<'INSTALLER'
#!/bin/sh
set -eu
printf '%s\n' "$0" >> "$TACIT_EXEC_LOG"
printf '%s\n' "$*" >> "$TACIT_ARGS_LOG"
[ "$#" -eq 4 ] && [ "$1" = --edition ] && [ "$2" = enkoja ] && [ "$3" = --languages ] && [ "$4" = ja,en,ko ]
if IFS= read -r answer; then
    printf 'Tacit installer must run without interactive stdin\n' >&2
    exit 92
fi
[ "${MOCK_TACIT_INSTALL_STATUS:-0}" -eq 0 ] || exit "$MOCK_TACIT_INSTALL_STATUS"
mkdir -p "$HOME/Library/Input Methods/tacit.app" "$HOME/.local/bin"
cp "$MOCK_TOOL" "$HOME/.local/bin/tacit"
cp "$MOCK_TOOL" "$HOME/.local/bin/tacit-config"
INSTALLER
cat > "$root/curl" <<'CURL'
#!/bin/sh
set -eu
[ "$#" -eq 4 ] && [ "$1" = -fsSL ] && [ "$3" = -o ]
case "$2" in
    https://starship.rs/install.sh) cp "$MOCK_INSTALLER" "$4" ;;
    https://github.com/iamallyouneed/tacit/releases/latest/download/install.sh)
        printf '%s\n' "$2" >> "$TACIT_DOWNLOAD_LOG"
        printf '%s\n' "$4" > "$TACIT_PATH_LOG"
        # A failed transfer may leave partial executable content behind.
        cp "$MOCK_TACIT_INSTALLER" "$4"
        exit "${MOCK_TACIT_DOWNLOAD_STATUS:-0}" ;;
    *) exit 99 ;;
esac
CURL
cp "$root/curl" "$root/bin/curl"
chmod +x "$root/bin/curl"
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
MOCK_TACIT_INSTALLER="$root/tacit-installer"
TACIT_DOWNLOAD_LOG="$root/tacit-download-log"
TACIT_EXEC_LOG="$root/tacit-exec-log"
TACIT_PATH_LOG="$root/tacit-path-log"
TACIT_ARGS_LOG="$root/tacit-args-log"
COMPILER_LOG="$root/compiler-log"
COMPILER_PATH_LOG="$root/compiler-path-log"
COMPILER_EXEC_LOG="$root/compiler-exec-log"
export COMPILER_LOG COMPILER_PATH_LOG COMPILER_EXEC_LOG
mkdir -p "$root/tmp"
TMPDIR="$root/tmp"
export TMPDIR MOCK_TACIT_INSTALLER TACIT_DOWNLOAD_LOG TACIT_EXEC_LOG TACIT_PATH_LOG TACIT_ARGS_LOG
export TEST_LOG APT_CACHE_LOG APT_UPDATE_MARKER MOCK_BIN MOCK_TOOL MOCK_NVIM
export MOCK_NVIM_VERSION MOCK_NODE_VERSION MOCK_TREE_SITTER_VERSION MOCK_OS MOCK_INSTALLER MOCK_CURL MOCK_NO_CANDIDATE

# Dry-run previews Homebrew installs without creating tools.
HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" --dry-run > "$root/preview"
[ ! -e "$root/log" ]
[ ! -e "$root/bin/nvim" ]
[ ! -e "$TACIT_DOWNLOAD_LOG" ]
[ ! -e "$TACIT_EXEC_LOG" ]
[ ! -e "$root/home/Library" ]
set -- "$root/tmp"/*
[ ! -e "$1" ]
case "$(cat "$root/preview")" in *'HOMEBREW_NO_ASK=1 brew install'*) ;; *) exit 1 ;; esac
case "$(cat "$root/preview")" in *'latest Tacit'*'enkoja'*'ja,en,ko'*) ;; *) exit 1 ;; esac
[ ! -e "$TACIT_ARGS_LOG" ]
[ "$(cat "$COMPILER_LOG")" = cc ]
[ ! -e "$COMPILER_EXEC_LOG" ]
while IFS= read -r compiler_path; do
    case "$compiler_path" in "$TMPDIR"/dotfiles-compiler.*/*) ;; *) exit 1 ;; esac
    [ ! -e "$compiler_path" ]
    [ ! -e "${compiler_path%/*}" ]
done < "$COMPILER_PATH_LOG"

# A relative TMPDIR must keep source/output paths and cleanup valid after cd.
for compiler_result in success headers; do
    (
        CDPATH='' cd -- "$root"
        compiler_failure=
        [ "$compiler_result" != headers ] || compiler_failure=headers
        status=0
        TMPDIR=tmp MOCK_COMPILER_FAILURE="$compiler_failure" HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" --dry-run > "$root/relative-preview" 2> "$root/error" || status=$?
        if [ "$compiler_result" = success ]; then
            [ "$status" -eq 0 ]
        else
            [ "$status" -eq 1 ]
            case "$(cat "$root/error")" in *'fatal error: stdint.h: No such file or directory'*) ;; *) exit 1 ;; esac
        fi
        while IFS= read -r compiler_path; do
            case "$compiler_path" in "$root"/tmp/dotfiles-compiler.*/*) ;; *) exit 1 ;; esac
            [ ! -e "$compiler_path" ]
            [ ! -e "${compiler_path%/*}" ]
        done < "$COMPILER_PATH_LOG"
        set -- tmp/*
        [ ! -e "$1" ]
    )
done

# The linked artifact is never executed; noexec access must not reject it.
MOCK_COMPILER_FAILURE=noexec-output HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" --dry-run > "$root/nonexec-preview"
[ ! -e "$COMPILER_EXEC_LOG" ]
while IFS= read -r compiler_path; do
    [ ! -e "$compiler_path" ]
    [ ! -e "${compiler_path%/*}" ]
done < "$COMPILER_PATH_LOG"

# Use the first available compiler, never silently bypass a broken one.
cp "$root/compiler" "$root/bin/gcc"
cp "$root/compiler" "$root/bin/clang"
HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" --dry-run > "$root/compiler-preview"
[ "$(cat "$COMPILER_LOG")" = cc ]
rm "$root/bin/cc"
HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" --dry-run > "$root/compiler-preview"
[ "$(cat "$COMPILER_LOG")" = gcc ]
rm "$root/bin/gcc"
HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" --dry-run > "$root/compiler-preview"
[ "$(cat "$COMPILER_LOG")" = clang ]
rm "$root/bin/clang"
if HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" --dry-run > "$root/compiler-preview" 2> "$root/error"; then
    printf 'Missing C compiler should fail preflight\n' >&2
    exit 1
fi
case "$(cat "$root/error")" in *'a C compiler (cc, gcc, or clang)'*) ;; *) exit 1 ;; esac
cp "$root/compiler" "$root/bin/cc"
cp "$root/compiler" "$root/bin/gcc"

# Both real initialization and previews reject headers/linker failures before
# packages, network requests, Git configuration, backups or config links.
mkdir -p "$root/compiler-home/.config/nvim"
printf 'keep shell\n' > "$root/compiler-home/.zshrc"
printf 'keep editor\n' > "$root/compiler-home/.config/nvim/local.txt"
printf '[user]\n    name = Keep User\n' > "$root/compiler-home/.gitconfig"
for compiler_failure in headers linker no-output empty-output; do
    for compiler_mode in install dry-run; do
        set --
        [ "$compiler_mode" = install ] || set -- --dry-run
        if MOCK_COMPILER_FAILURE="$compiler_failure" TEST_LOG="$root/broken-compiler-log" HOME="$root/compiler-home" XDG_CONFIG_HOME="$root/compiler-home/.config" PATH="$root/bin" "$repo/initialize.sh" --no-macos "$@" > "$root/compiler-preview" 2> "$root/error"; then
            printf 'Broken C toolchain should reject initialization (%s, %s)\n' "$compiler_failure" "$compiler_mode" >&2
            exit 1
        fi
        case "$(cat "$root/error")" in *'C standard library development headers and linker manually'*) ;; *) exit 1 ;; esac
        case "$compiler_failure" in
            headers) case "$(cat "$root/error")" in *'fatal error: stdint.h: No such file or directory'*) ;; *) exit 1 ;; esac ;;
            linker) case "$(cat "$root/error")" in *'ld: cannot find Scrt1.o'*) ;; *) exit 1 ;; esac ;;
            no-output|empty-output) case "$(cat "$root/error")" in *'did not produce a nonempty program file'*) ;; *) exit 1 ;; esac ;;
        esac
        [ "$(cat "$COMPILER_LOG")" = cc ]
        [ ! -e "$root/broken-compiler-log" ]
        [ ! -e "$TACIT_DOWNLOAD_LOG" ]
        [ ! -e "$TACIT_EXEC_LOG" ]
        [ ! -e "$COMPILER_EXEC_LOG" ]
        [ ! -e "$root/compiler-home/.dotfiles-backups" ]
        [ ! -e "$root/compiler-home/.local" ]
        [ ! -L "$root/compiler-home/.zshrc" ]
        [ ! -L "$root/compiler-home/.config/nvim" ]
        [ "$(cat "$root/compiler-home/.zshrc")" = 'keep shell' ]
        [ "$(cat "$root/compiler-home/.config/nvim/local.txt")" = 'keep editor' ]
        [ "$(cat "$root/compiler-home/.gitconfig")" = '[user]
    name = Keep User' ]
        while IFS= read -r compiler_path; do
            [ ! -e "$compiler_path" ]
            [ ! -e "${compiler_path%/*}" ]
        done < "$COMPILER_PATH_LOG"
        set -- "$root/tmp"/*
        [ ! -e "$1" ]
    done
done
rm "$root/bin/gcc"
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
printf 'n\n' | HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/mac-output"
[ "$(cat "$TACIT_ARGS_LOG")" = '--edition enkoja --languages ja,en,ko' ]
[ "$(cat "$root/log")" = 'brew install neovim
brew install ripgrep
brew install fd
brew install starship
brew install eza
brew install gh
brew install lsof' ]
[ "$(cat "$TACIT_DOWNLOAD_LOG")" = 'https://github.com/iamallyouneed/tacit/releases/latest/download/install.sh' ]
[ -x "$root/home/.local/bin/tacit" ]
[ -x "$root/home/.local/bin/tacit-config" ]
[ -d "$root/home/Library/Input Methods/tacit.app" ]
tacit_path=$(cat "$TACIT_PATH_LOG")
case "$tacit_path" in "$root/tmp"/dotfiles-tacit.*/install.sh) ;; *) exit 1 ;; esac
[ "$(cat "$TACIT_EXEC_LOG")" = "$tacit_path" ]
[ ! -e "${tacit_path%/*}" ]
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
: > "$TACIT_DOWNLOAD_LOG"
: > "$TACIT_EXEC_LOG"
: > "$TACIT_ARGS_LOG"
TEST_LOG="$root/mac-rerun-log" HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/mac-rerun"
[ ! -e "$root/mac-rerun-log" ]
[ "$(cat "$TACIT_ARGS_LOG")" = '--edition enkoja --languages ja,en,ko' ]
[ "$(cat "$TACIT_DOWNLOAD_LOG")" = 'https://github.com/iamallyouneed/tacit/releases/latest/download/install.sh' ]
[ "$(cat "$TACIT_EXEC_LOG")" = "$(cat "$TACIT_PATH_LOG")" ]
tacit_path=$(cat "$TACIT_PATH_LOG")
[ ! -e "${tacit_path%/*}" ]

# Download and installer failures retain their status and clean private storage.
for failure in download installer; do
    : > "$TACIT_EXEC_LOG"
    status=0
    if [ "$failure" = download ]; then
        MOCK_TACIT_DOWNLOAD_STATUS=23 HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/error" 2>&1 || status=$?
        [ "$status" -eq 23 ]
        [ ! -s "$TACIT_EXEC_LOG" ]
    else
        MOCK_TACIT_INSTALL_STATUS=42 HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/error" 2>&1 || status=$?
        [ "$status" -eq 42 ]
        [ "$(cat "$TACIT_EXEC_LOG")" = "$(cat "$TACIT_PATH_LOG")" ]
    fi
    tacit_path=$(cat "$TACIT_PATH_LOG")
    [ ! -e "${tacit_path%/*}" ]
done
: > "$TACIT_DOWNLOAD_LOG"
: > "$TACIT_EXEC_LOG"
HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" --dry-run > "$root/mac-existing-preview"
[ ! -s "$TACIT_DOWNLOAD_LOG" ]
[ ! -s "$TACIT_EXEC_LOG" ]
set -- "$root/tmp"/*
[ ! -e "$1" ]
# macOS requires curl even when every CLI and Tacit are already installed.
rm "$root/bin/curl"
if HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/error" 2>&1; then
    printf 'Missing macOS curl should fail preflight\n' >&2
    exit 1
fi
case "$(cat "$root/error")" in *'prerequisite: curl'*) ;; *) exit 1 ;; esac
[ ! -s "$TACIT_DOWNLOAD_LOG" ]
cp "$root/curl" "$root/bin/curl"
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

# Respect the CLI selected by the caller, including npm's 0.27.1 executable.
# Adding ~/.local/bin must not promote an older CLI over the caller's PATH.
MOCK_TREE_SITTER_VERSION=0.27.1
export MOCK_TREE_SITTER_VERSION
printf '#!/bin/sh\nprintf "tree-sitter 0.25.0\\n"\n' > "$root/home/.local/bin/tree-sitter"
chmod +x "$root/home/.local/bin/tree-sitter"
for selected_path in "$root/bin" "$root/bin:$root/home/.local/bin"; do
    TEST_LOG="$root/npm-cli-log" HOME="$root/home" PATH="$selected_path" "$repo/scripts/install-tools.sh" --dry-run > "$root/npm-cli-preview"
    [ ! -e "$root/npm-cli-log" ]
done
# An explicitly selected old binary must fail with its actual path and version.
if HOME="$root/home" PATH="$root/home/.local/bin:$root/bin" "$repo/scripts/install-tools.sh" --dry-run > "$root/error" 2>&1; then
    printf 'An explicitly selected old CLI should not be bypassed\n' >&2
    exit 1
fi
case "$(cat "$root/error")" in *"$root/home/.local/bin/tree-sitter"*'tree-sitter 0.25.0'*) ;; *) exit 1 ;; esac
rm "$root/home/.local/bin/tree-sitter"

# Missing, unexecutable and unsupported CLI versions are different failures.
cp "$root/bin/tree-sitter" "$root/tree-sitter-tool"
rm "$root/bin/tree-sitter"
if HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" --dry-run > "$root/error" 2>&1; then
    printf 'Missing tree-sitter executable should fail preflight\n' >&2
    exit 1
fi
case "$(cat "$root/error")" in *'Missing required editor setup prerequisite: tree-sitter-cli'*'PATH'*'npm prefix -g'*) ;; *) exit 1 ;; esac
cat > "$root/bin/tree-sitter" <<'BROKEN_CLI'
#!/bin/sh
printf 'error while loading shared libraries: libexample.so\n' >&2
exit 127
BROKEN_CLI
chmod +x "$root/bin/tree-sitter"
if HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" --dry-run > "$root/error" 2>&1; then
    printf 'An installed but broken CLI should fail preflight\n' >&2
    exit 1
fi
case "$(cat "$root/error")" in *'libexample.so'*"$root/bin/tree-sitter"*'exit 127'*) ;; *) exit 1 ;; esac
cp "$root/tree-sitter-tool" "$root/bin/tree-sitter"

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

# A successful manager can leave an unlinked or out-of-PATH executable missing.
for platform in Darwin Linux; do
    rm "$root/bin/rg"
    : > "$TACIT_DOWNLOAD_LOG"
    if MOCK_OS="$platform" MOCK_SKIP_PACKAGE=ripgrep HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/error" 2>&1; then
        printf 'A successful package operation without rg must fail setup\n' >&2
        exit 1
    fi
    case "$(cat "$root/error")" in *'required command rg is still unavailable on PATH'*'Repair the package links or PATH'*) ;; *) exit 1 ;; esac
    [ ! -s "$TACIT_DOWNLOAD_LOG" ]
    # Preview still reports work rather than requiring installation side effects.
    MOCK_OS="$platform" MOCK_SKIP_PACKAGE=ripgrep HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" --dry-run > "$root/postcheck-preview"
    cp "$root/tool" "$root/bin/rg"
done
rm "$root/home/.local/bin/starship"
if MOCK_SKIP_STARSHIP=1 HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/error" 2>&1; then
    printf 'A successful Starship installer without its executable must fail setup\n' >&2
    exit 1
fi
case "$(cat "$root/error")" in *'required command starship is still unavailable on PATH'*) ;; *) exit 1 ;; esac
cp "$root/tool" "$root/home/.local/bin/starship"

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
# Linux must never download or execute Tacit, even when already installed.
[ ! -s "$TACIT_DOWNLOAD_LOG" ]
[ ! -s "$TACIT_EXEC_LOG" ]
MOCK_OS=Darwin
export MOCK_OS
rm "$root/bin/brew"
if TEST_LOG="$root/no-brew-log" HOME="$root/home" PATH="$root/bin" "$repo/scripts/install-tools.sh" > "$root/error" 2>&1; then
    printf 'Missing Homebrew should fail\n' >&2
    exit 1
fi
[ ! -e "$root/no-brew-log" ]
printf 'Mocked macOS/Linux mappings, Neovim/prerequisite/apt preflights, previews and repeat-run tests passed.\n'
