#!/bin/sh
set -eu

[ "$#" -eq 0 ] || { [ "$#" -eq 1 ] && [ "$1" = --dry-run ]; } || {
    printf 'Usage: %s [--dry-run]\n' "$0" >&2
    exit 2
}
dry_run=0
[ "$#" -eq 0 ] || dry_run=1

# Include locally installed tools without overriding the caller's selected CLI.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH="$PATH:$HOME/.local/bin" ;;
esac
export PATH
os=$(uname -s)
case "$os" in
    Darwin|Linux) ;;
    *) printf 'Unsupported OS: %s\n' "$os" >&2; exit 2 ;;
esac

# Parse semantic versions into normalized numeric components.
parse_version() {
    version_text=${1#v}
    version_text=${version_text%%+*}
    version_prerelease=0
    case "$version_text" in
        *-*) version_prerelease=1; version_text=${version_text%%-*} ;;
    esac
    case "$version_text" in
        ''|*[!0-9.]*|.*|*..*|*.) return 1 ;;
    esac
    version_major=${version_text%%.*}
    case "$version_text" in
        *.*) version_remainder=${version_text#*.} ;;
        *) return 1 ;;
    esac
    case "$version_remainder" in
        *.*)
            version_minor=${version_remainder%%.*}
            version_patch=${version_remainder#*.} ;;
        *) version_minor=$version_remainder; version_patch=0 ;;
    esac
    for version_component in "$version_major" "$version_minor" "$version_patch"; do
        case "$version_component" in ''|*[!0-9]*) return 1 ;; esac
    done
    while [ "${version_major#0}" != "$version_major" ]; do version_major=${version_major#0}; done
    while [ "${version_minor#0}" != "$version_minor" ]; do version_minor=${version_minor#0}; done
    while [ "${version_patch#0}" != "$version_patch" ]; do version_patch=${version_patch#0}; done
    [ -n "$version_major" ] || version_major=0
    [ -n "$version_minor" ] || version_minor=0
    [ -n "$version_patch" ] || version_patch=0
}

version_at_least() {
    parse_version "$1" || return 1
    actual_major=$version_major
    actual_minor=$version_minor
    actual_patch=$version_patch
    actual_prerelease=$version_prerelease
    parse_version "$2" || return 1
    required_major=$version_major
    required_minor=$version_minor
    required_patch=$version_patch
    [ "$actual_major" -gt "$required_major" ] && return 0
    [ "$actual_major" -lt "$required_major" ] && return 1
    [ "$actual_minor" -gt "$required_minor" ] && return 0
    [ "$actual_minor" -lt "$required_minor" ] && return 1
    [ "$actual_patch" -gt "$required_patch" ] && return 0
    [ "$actual_patch" -lt "$required_patch" ] && return 1
    [ "$actual_prerelease" -eq 0 ]
}

nvim_is_supported() {
    nvim_output=$(nvim --version 2>/dev/null) || return 1
    newline='
'
    nvim_first_line=${nvim_output%%"$newline"*}
    case "$nvim_first_line" in
        'NVIM v'*) nvim_version=${nvim_first_line#NVIM v} ;;
        *) return 1 ;;
    esac
    version_at_least "$nvim_version" 0.12.0
}

if command -v nvim >/dev/null 2>&1; then
    if ! nvim_is_supported; then
        printf 'Neovim 0.12 or newer is required; the existing nvim is missing a valid version or is too old. Install a recent official Neovim and rerun.\n' >&2
        exit 1
    fi
elif [ "$os" = Linux ]; then
    printf 'Neovim 0.12 or newer is required. Install a recent official Neovim first; Linux distribution packages are not used for Neovim.\n' >&2
    exit 1
fi

# Even previews compile/link privately: no binary execution or persistent changes.
probe_c_toolchain() (
    compiler=
    for candidate in cc gcc clang; do
        if compiler_path=$(command -v "$candidate" 2>/dev/null); then
            compiler=$candidate
            case "$compiler_path" in
                /*) ;;
                *) compiler_path="$PWD/$compiler_path" ;;
            esac
            break
        fi
    done
    if [ -z "$compiler" ]; then
        printf 'Missing required editor setup prerequisite: a C compiler (cc, gcc, or clang). Install one manually before running the editor setup.\n' >&2
        exit 1
    fi

    probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-compiler.XXXXXXXX") || exit $?
    case "$probe_dir" in
        /*) ;;
        *) probe_dir="$PWD/$probe_dir" ;;
    esac
    trap 'rm -rf "$probe_dir"' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    CDPATH='' cd -- "$probe_dir" || exit $?
    printf '%s\n' '#include <stdint.h>
#include <stdlib.h>
int main(void) {
    uint_least8_t *value = malloc(sizeof *value);
    if (value == NULL) return EXIT_FAILURE;
    *value = 0;
    free(value);
    return EXIT_SUCCESS;
}' > "$probe_dir/probe.c" || exit $?
    if ! "$compiler_path" "$probe_dir/probe.c" -o "$probe_dir/probe"; then
        printf 'The C toolchain (%s) could not compile and link a program using stdint.h and stdlib.h. Install a working C compiler, C standard library development headers and linker manually before running the editor setup; see the compiler diagnostic above.\n' "$compiler" >&2
        exit 1
    fi
    if [ ! -f "$probe_dir/probe" ] || [ ! -s "$probe_dir/probe" ]; then
        printf 'The C toolchain (%s) did not produce a nonempty program file. Install a working C compiler, C standard library development headers and linker manually before running the editor setup.\n' "$compiler" >&2
        exit 1
    fi
)

check_tree_sitter() {
    if ! tree_sitter_command=$(command -v tree-sitter); then
        printf 'Missing required editor setup prerequisite: tree-sitter-cli 0.26.1 or newer. The tree-sitter executable must be on PATH.\n' >&2
        printf '%s\n' 'For npm installations, check command -v tree-sitter, tree-sitter --version, and npm prefix -g; a project-local npm installation is not automatically on PATH.' >&2
        return 1
    fi
    tree_sitter_status=0
    tree_sitter_output=$("$tree_sitter_command" --version) || tree_sitter_status=$?
    if [ "$tree_sitter_status" -ne 0 ]; then
        printf 'Installed Tree-sitter CLI could not run: %s --version failed (exit %s). Fix the execution error above or select a working CLI on PATH.\n' "$tree_sitter_command" "$tree_sitter_status" >&2
        return 1
    fi
    case "$tree_sitter_output" in
        'tree-sitter '*) tree_sitter_version=${tree_sitter_output#tree-sitter } ;;
        *) tree_sitter_version=$tree_sitter_output ;;
    esac
    tree_sitter_version=${tree_sitter_version%% *}
    if ! version_at_least "$tree_sitter_version" 0.26.1; then
        printf 'tree-sitter-cli 0.26.1 or newer is required; selected %s reported: %s\n' "$tree_sitter_command" "$tree_sitter_output" >&2
        return 1
    fi
}

preflight_toolchain() {
    preflight_ok=1
    if ! command -v node >/dev/null 2>&1; then
        printf 'Missing required editor setup prerequisite: Node.js 22.22.2 or newer. Install it manually before running the editor setup.\n' >&2
        preflight_ok=0
    else
        node_version=$(node --version 2>/dev/null) || node_version=
        if ! version_at_least "$node_version" 22.22.2; then
            printf 'Node.js 22.22.2 or newer is required; install or upgrade it manually before running the editor setup.\n' >&2
            preflight_ok=0
        fi
    fi
    for prerequisite in npm go tar unzip gzip; do
        if ! command -v "$prerequisite" >/dev/null 2>&1; then
            printf 'Missing required editor setup prerequisite: %s. Install it manually before running the editor setup.\n' "$prerequisite" >&2
            preflight_ok=0
        fi
    done
    if ! command -v curl >/dev/null 2>&1; then
        if [ "$os" != Linux ] || command -v starship >/dev/null 2>&1; then
            printf 'Missing required editor setup prerequisite: curl. Install it manually before running the editor setup.\n' >&2
            preflight_ok=0
        fi
    fi
    if ! check_tree_sitter; then
        preflight_ok=0
    fi
    if ! probe_c_toolchain; then
        preflight_ok=0
    fi
    [ "$preflight_ok" -eq 1 ]
}

preflight_toolchain || exit 1

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
                command -v apt-cache >/dev/null 2>&1 || {
                    printf 'apt-cache is required to check package availability; install the apt package tools and rerun.\n' >&2
                    exit 1
                }
                sudo apt-get update
                for package in "$@"; do
                    if ! apt_policy=$(LC_ALL=C apt-cache policy "$package"); then
                        printf 'Could not check apt availability for %s; install it manually or use Ubuntu 24.04+ / Debian 13+.\n' "$package" >&2
                        exit 1
                    fi
                    case "$apt_policy" in
                        *'Candidate:'*)
                            apt_candidate=${apt_policy#*Candidate:}
                            apt_candidate=${apt_candidate%%'
'*}
                            while [ "${apt_candidate# }" != "$apt_candidate" ]; do apt_candidate=${apt_candidate# }; done
                            while [ "${apt_candidate% }" != "$apt_candidate" ]; do apt_candidate=${apt_candidate% }; done
                            case "$apt_candidate" in
                                ''|'(none)')
                                    printf 'No apt candidate is available for %s. Automatic installation supports Ubuntu 24.04+ and Debian 13+; install it manually or use a supported release.\n' "$package" >&2
                                    exit 1 ;;
                            esac ;;
                        *)
                            printf 'No apt candidate is available for %s. Automatic installation supports Ubuntu 24.04+ and Debian 13+; install it manually or use a supported release.\n' "$package" >&2
                            exit 1 ;;
                    esac
                done
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

if [ "$dry_run" -eq 0 ]; then
    if ! command -v nvim >/dev/null 2>&1 || ! nvim_is_supported; then
        printf 'The installed Neovim is not 0.12 or newer. Install a recent official Neovim and rerun.\n' >&2
        exit 1
    fi
fi

# Upstream looks for bundled files beside its installer; use a private directory.
install_tacit() (
    installer_dir=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-tacit.XXXXXXXX") || exit $?
    trap 'rm -rf "$installer_dir"' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    curl -fsSL https://github.com/iamallyouneed/tacit/releases/latest/download/install.sh -o "$installer_dir/install.sh" || exit $?
    /bin/sh "$installer_dir/install.sh"
)

if [ "$os" = Darwin ]; then
    printf 'Install/update: latest Tacit via official release installer\n'
    [ "$dry_run" -eq 1 ] || install_tacit
fi
