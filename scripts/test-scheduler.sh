#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$root/stubs" "$root/missing"
cat > "$root/stubs/uname" <<'EOF'
#!/bin/sh
printf '%s\n' "$MOCK_OS"
EOF
cat > "$root/stubs/id" <<'EOF'
#!/bin/sh
[ "$1" = -u ] || exit 2
printf '501\n'
EOF
cat > "$root/stubs/launchctl" <<'EOF'
#!/bin/sh
[ "${MOCK_UNAVAILABLE:-0}" = 0 ] || exit 1
case "$1" in
    print)
        [ "$2" != gui/501 ] || exit 0
        [ "$2" = gui/501/com.snowykr.dotfiles.update ] || exit 2
        [ -f "$MOCK_LOADED" ]; exit $?;;
    enable|bootstrap|bootout) printf '%s\n' "$*" >> "$MOCK_LOG";;
    *) exit 2;;
esac
[ "${MOCK_FAIL:-0}" = 0 ] || exit 1
case "$1" in bootstrap) : > "$MOCK_LOADED";; bootout) rm -f "$MOCK_LOADED";; esac
EOF
cat > "$root/stubs/systemctl" <<'EOF'
#!/bin/sh
[ "$1" = --user ] || exit 2
shift
[ "${MOCK_UNAVAILABLE:-0}" = 0 ] || exit 1
case "$1" in
    show-environment) exit 0;;
    is-enabled|is-active) [ -f "$MOCK_LOADED" ]; exit $?;;
    daemon-reload|enable|disable|restart) printf '%s\n' "$*" >> "$MOCK_LOG";;
    *) exit 2;;
esac
[ "${MOCK_FAIL:-0}" = 0 ] || exit 1
case "$1" in enable) : > "$MOCK_LOADED";; disable) rm -f "$MOCK_LOADED";; esac
EOF
chmod +x "$root/stubs/"*
cp "$root/stubs/uname" "$root/missing/uname"
cp "$root/stubs/id" "$root/missing/id"
PATH="$root/stubs:$PATH"
export PATH
run() { /bin/sh "$repo/scripts/scheduler.sh" "$1" "$checkout" "$state" ${2:+"$2"}; }
expect_failure() {
    if run "$@" > "$root/error"; then printf 'Expected scheduler failure\n' >&2; exit 1; fi
    ! grep -x enabled "$root/error"
}
# Literal punctuation includes XML characters, quotes, percent, dollar and backslash.
checkout="$root/repo space & < > \" ' % \$ \\"
initial_checkout=$checkout
for MOCK_OS in Darwin Linux; do
    checkout=$initial_checkout
    HOME="$root/$MOCK_OS home"
    XDG_CONFIG_HOME="$root/$MOCK_OS config & \" % \$ \\"
    XDG_STATE_HOME="$root/$MOCK_OS state & \" % \$ \\"
    state=$XDG_STATE_HOME/dotfiles
    # Explicit backend state wins over a stale caller/user-manager environment.
    XDG_STATE_HOME="$root/ignored state home"
    MOCK_LOG="$root/$MOCK_OS.mutations"
    MOCK_LOADED="$root/$MOCK_OS.loaded"
    export MOCK_OS HOME XDG_CONFIG_HOME XDG_STATE_HOME MOCK_LOG MOCK_LOADED
    [ "$(run status)" = disabled ]
    [ ! -e "$HOME" ] && [ ! -e "$XDG_CONFIG_HOME" ] && [ ! -e "$state" ]
    run enable --dry-run > "$root/preview"
    run disable --dry-run > "$root/preview"
    [ ! -e "$MOCK_LOG" ] && [ ! -e "$HOME" ] && [ ! -e "$state" ]
    [ "$(run enable)" = enabled ]
    [ "$(run status)" = enabled ]
    case "$MOCK_OS" in
        Darwin)
            definition=$HOME/Library/LaunchAgents/com.snowykr.dotfiles.update.plist
            grep -F '<string>/bin/sh</string>' "$definition"
            grep -F '<string>update</string>' "$definition"
            for minute in 0 15 30 45; do
                grep -F "<key>Minute</key><integer>$minute</integer>" "$definition"
            done
            ! grep -E 'KeepAlive|RunAtLoad|Wake' "$definition"
            grep -F '&amp; &lt; &gt; &quot; &apos; % $ \' "$definition"
            grep -F '<key>StandardOutPath</key>' "$definition"
            grep -F '<key>StandardErrorPath</key>' "$definition"
            grep -F 'scheduler.log</string>' "$definition"
            grep -F '<key>XDG_STATE_HOME</key>' "$definition"
            grep -F 'state &amp; &quot; % $ \' "$definition"
            if command -v plutil >/dev/null; then plutil -lint -- "$definition"; fi
            ;;
        Linux)
            definition=$XDG_CONFIG_HOME/systemd/user/dotfiles-update.service
            timer=$XDG_CONFIG_HOME/systemd/user/dotfiles-update.timer
            grep -x 'Type=oneshot' "$definition"
            grep -x 'TimeoutStartSec=120' "$definition"
            grep -F 'ExecStart=/bin/sh "' "$definition"
            grep -F '\" '\'' %% $$ \\/maintain.sh" update' "$definition"
            grep -F 'Environment="XDG_STATE_HOME=' "$definition"
            grep -F 'state & \" %% $ \\"' "$definition"
            grep -x 'OnCalendar=\*-\*-\* \*:0/15:00' "$timer"
            grep -x 'Persistent=true' "$timer"
            ;;
    esac
    grep -F '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin' "$definition"
    ! grep -F 'ignored state home' "$definition"
    cp "$definition" "$root/before"
    [ "$(run enable)" = enabled ]
    cmp "$definition" "$root/before"
    # Refresh changed descriptors with the new checkout without accumulating jobs.
    checkout="$checkout changed"
    [ "$(run enable)" = enabled ]
    ! cmp -s "$definition" "$root/before"
    grep -F ' changed/maintain.sh' "$definition"
    # Neither status nor preview can touch descriptor contents or scheduler state.
    cp "$definition" "$root/before"
    cp "$MOCK_LOG" "$root/log-before"
    run status > "$root/status"
    run enable --dry-run > "$root/preview"
    run disable --dry-run > "$root/preview"
    cmp "$definition" "$root/before"
    cmp "$MOCK_LOG" "$root/log-before"
    # Preserve neighboring user work; repeated disable is a no-op.
    printf 'user work\n' > "$(dirname "$definition")/unrelated.conf"
    [ "$(run disable)" = disabled ]
    [ ! -e "$definition" ]
    [ "$(run status)" = disabled ]
    cp "$MOCK_LOG" "$root/log-before"
    [ "$(run disable)" = disabled ]
    cmp "$MOCK_LOG" "$root/log-before"
    [ "$(cat "$(dirname "$definition")/unrelated.conf")" = 'user work' ]
    # An unmanaged file or symlink at our name must not be replaced or removed.
    printf 'user work\n' > "$definition"
    expect_failure enable
    expect_failure disable
    [ "$(cat "$definition")" = 'user work' ]
    rm "$definition"
    ln -s "$(dirname "$definition")/unrelated.conf" "$definition"
    expect_failure enable
    expect_failure disable
    [ -L "$definition" ]
    rm "$definition"
    # Unreachable native managers and failed registration are explicit errors.
    MOCK_UNAVAILABLE=1; export MOCK_UNAVAILABLE
    expect_failure enable
    [ ! -e "$definition" ]
    MOCK_UNAVAILABLE=0; export MOCK_UNAVAILABLE
    MOCK_FAIL=1; export MOCK_FAIL
    expect_failure enable
    [ "$(run status)" = disabled ]
    MOCK_FAIL=0; export MOCK_FAIL
    run disable > "$root/disabled"
    # command-not-found must never fall through to a real scheduler.
    if PATH="$root/missing" /bin/sh "$repo/scripts/scheduler.sh" enable "$checkout" "$state" > "$root/error"; then exit 1; fi
    case "$MOCK_OS" in
        Darwin) grep -F 'bootout gui/501/com.snowykr.dotfiles.update' "$MOCK_LOG";;
        Linux) grep -F 'disable --now dotfiles-update.timer' "$MOCK_LOG";;
    esac
done
MOCK_OS=FreeBSD; export MOCK_OS
expect_failure enable
MOCK_OS=Linux; export MOCK_OS
checkout=relative
expect_failure enable
checkout="$root/newline
path"
expect_failure enable
checkout="$root/carriage$(printf '\r')return"
expect_failure enable
printf 'Isolated native scheduler tests passed.\n'
