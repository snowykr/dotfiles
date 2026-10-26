#!/bin/sh
set -eu

[ "$#" -eq 0 ] || { [ "$#" -eq 1 ] && [ "$1" = --dry-run ]; } || {
    printf 'Usage: %s [--dry-run]\n' "$0" >&2
    exit 2
}
dry_run=0
[ "$#" -eq 0 ] || dry_run=1

# Include tools installed by this script even before the shell config is loaded.
export PATH="$HOME/.local/bin:$PATH"
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
    if ! command -v tree-sitter >/dev/null 2>&1; then
        printf 'Missing required editor setup prerequisite: tree-sitter-cli 0.26.1 or newer. Install it manually before running the editor setup.\n' >&2
        preflight_ok=0
    else
        tree_sitter_output=$(tree-sitter --version 2>/dev/null) || tree_sitter_output=
        case "$tree_sitter_output" in
            'tree-sitter '*) tree_sitter_version=${tree_sitter_output#tree-sitter } ;;
            *) tree_sitter_version=$tree_sitter_output ;;
        esac
        tree_sitter_version=${tree_sitter_version%% *}
        if ! version_at_least "$tree_sitter_version" 0.26.1; then
            printf 'tree-sitter-cli 0.26.1 or newer is required; install or upgrade it manually before running the editor setup.\n' >&2
            preflight_ok=0
        fi
    fi
    if ! command -v cc >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1 && ! command -v clang >/dev/null 2>&1; then
        printf 'Missing required editor setup prerequisite: a C compiler (cc, gcc, or clang). Install one manually before running the editor setup.\n' >&2
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
