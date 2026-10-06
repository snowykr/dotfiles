#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
root=$(mktemp -d)
root=$(CDPATH= cd -- "$root" && pwd -P)
updater=
cleanup_tests() {
    if [ -n "$updater" ] && kill -0 "$updater" 2>/dev/null; then
        kill -TERM "$updater"
        wait "$updater" || :
    fi
    rm -rf "$root"
}
trap cleanup_tests EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$root/home" "$root/bin" "$root/publisher/scripts" "$root/publisher/shell"
export HOME="$root/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME='Dotfiles Test' GIT_AUTHOR_EMAIL='dotfiles@example.test'
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
REAL_GIT=$(command -v git)
REAL_SLEEP=$(command -v sleep)
REAL_PS=$(command -v ps)
export REAL_GIT REAL_SLEEP REAL_PS
FORBIDDEN_LOG="$root/forbidden"
SCHEDULER_LOG="$root/scheduler"
export FORBIDDEN_LOG SCHEDULER_LOG

assert_eq() {
    if [ "$1" != "$2" ]; then
        printf 'Expected: %s\nActual: %s\n' "$2" "$1" >&2
        exit 1
    fi
}

git init -q --bare --initial-branch=main "$root/remote.git"
git init -q --initial-branch=main "$root/publisher"
cp "$repo/maintain.sh" "$root/publisher/maintain.sh"
printf '%s\n' '#!/bin/sh' 'printf "unexpected initialization\n" >> "$FORBIDDEN_LOG"' > "$root/publisher/initialize.sh"
printf '%s\n' '#!/bin/sh' 'printf "scheduler %s\n" "$*" >> "$SCHEDULER_LOG"' > "$root/publisher/scripts/scheduler.sh"
printf 'alias hr=herdr\n' > "$root/publisher/shell/common.sh"
printf 'ignored-local.txt\n' > "$root/publisher/.gitignore"
git -C "$root/publisher" add .
git -C "$root/publisher" commit -qm 'test: initial configuration'
git -C "$root/publisher" remote add origin "$root/remote.git"
git -C "$root/publisher" push -q origin main
old=$(git -C "$root/publisher" rev-parse HEAD)

new_checkout() {
    case_name=$1
    checkout="$root/checkouts/$case_name"
    git clone -q "$root/remote.git" "$checkout"
    state_home="$root/state/$case_name"
}

run_maintain() {
    XDG_STATE_HOME="$state_home" /bin/sh "$checkout/maintain.sh" "$@"
}

# Clone before publication so these checkouts really are behind the remote.
for name in clean dry dirty staged untracked ignored feature detached diverged concurrent mid-fetch switch-fetch head-fetch interrupted timeout; do
    new_checkout "$name"
done
printf 'alias fresh=true\n' >> "$root/publisher/shell/common.sh"
git -C "$root/publisher" add shell/common.sh
printf 'new remote tracked file\n' > "$root/publisher/ignored-local.txt"
git -C "$root/publisher" add -f ignored-local.txt
git -C "$root/publisher" commit -qm 'test: publish updated configuration'
git -C "$root/publisher" push -q origin main
latest=$(git -C "$root/publisher" rev-parse HEAD)

case_name=clean
checkout="$root/checkouts/$case_name"
state_home="$root/state/$case_name"
printf '%s\n' '#!/bin/sh' 'printf "unexpected post-merge hook\n" >> "$FORBIDDEN_LOG"' > "$checkout/.git/hooks/post-merge"
chmod +x "$checkout/.git/hooks/post-merge"
run_maintain update > "$root/clean-output"
assert_eq "$(git -C "$checkout" rev-parse HEAD)" "$latest"
assert_eq "$(git -C "$checkout" status --porcelain)" ''
[ ! -e "$state_home/dotfiles/update.lock" ]
[ -f "$state_home/dotfiles/update.log" ]
run_maintain update > "$root/repeat-output"
case "$(cat "$root/repeat-output")" in *"Up to date:"*) ;; *) exit 1 ;; esac
[ ! -e "$FORBIDDEN_LOG" ]
[ ! -e "$SCHEDULER_LOG" ]

case_name=dry
checkout="$root/checkouts/$case_name"
state_home="$root/state/$case_name"
cp "$checkout/.git/index" "$root/dry-index"
run_maintain update --dry-run > "$root/dry-output"
cmp "$checkout/.git/index" "$root/dry-index"
assert_eq "$(git -C "$checkout" rev-parse HEAD)" "$old"
assert_eq "$(git -C "$checkout" rev-parse origin/main)" "$old"
[ ! -e "$state_home" ]
[ ! -e "$checkout/.git/FETCH_HEAD" ]

for case_name in dirty staged untracked feature detached diverged; do
    checkout="$root/checkouts/$case_name"
    state_home="$root/state/$case_name"
    case "$case_name" in
        dirty) printf 'local edit\n' >> "$checkout/shell/common.sh" ;;
        staged) printf 'staged edit\n' >> "$checkout/shell/common.sh"; git -C "$checkout" add shell/common.sh ;;
        untracked) printf 'keep me\n' > "$checkout/local.txt" ;;
        feature) git -C "$checkout" switch -q -c work ;;
        detached) git -C "$checkout" checkout -q --detach ;;
        diverged)
            printf 'local commit\n' >> "$checkout/shell/common.sh"
            git -C "$checkout" add shell/common.sh
            git -C "$checkout" commit -qm 'test: local divergent work' ;;
    esac
    before_head=$(git -C "$checkout" rev-parse HEAD)
    before_status=$(git -C "$checkout" status --porcelain)
    before_contents=$(cat "$checkout/shell/common.sh")
    run_maintain update > "$root/$case_name-output"
    assert_eq "$(git -C "$checkout" rev-parse HEAD)" "$before_head"
    assert_eq "$(git -C "$checkout" status --porcelain)" "$before_status"
    assert_eq "$(cat "$checkout/shell/common.sh")" "$before_contents"
    case "$(cat "$root/$case_name-output")" in *"Skipped:"*) ;; *) exit 1 ;; esac
    [ ! -e "$state_home/dotfiles/update.lock" ]
done

# Ignored files can be invisible to status but must not be overwritten by checkout.
case_name=ignored
checkout="$root/checkouts/$case_name"
state_home="$root/state/$case_name"
printf 'ignored user work\n' > "$checkout/ignored-local.txt"
if run_maintain update > "$root/ignored-output" 2>&1; then
    printf 'An ignored-file collision should reject the fast-forward\n' >&2
    exit 1
fi
assert_eq "$(cat "$checkout/ignored-local.txt")" 'ignored user work'
assert_eq "$(git -C "$checkout" rev-parse HEAD)" "$old"
[ ! -e "$state_home/dotfiles/update.lock" ]

new_checkout ahead
printf 'ahead\n' >> "$checkout/shell/common.sh"
git -C "$checkout" add shell/common.sh
git -C "$checkout" commit -qm 'test: local ahead work'
before_head=$(git -C "$checkout" rev-parse HEAD)
run_maintain update > "$root/ahead-output"
assert_eq "$(git -C "$checkout" rev-parse HEAD)" "$before_head"

new_checkout rewind
# A rewritten upstream must not reset the local checkout.
git -C "$root/publisher" push -q --force origin "$old:refs/heads/main"
run_maintain update > "$root/rewind-output"
assert_eq "$(git -C "$checkout" rev-parse HEAD)" "$latest"
git -C "$root/publisher" push -q origin main

new_checkout network-failure
git -C "$checkout" remote set-url origin "$root/missing.git"
if run_maintain update > "$root/network-output" 2>&1; then
    printf 'Fetch failure should return nonzero\n' >&2
    exit 1
fi
assert_eq "$(git -C "$checkout" rev-parse HEAD)" "$latest"
[ ! -e "$state_home/dotfiles/update.lock" ]
case "$(cat "$state_home/dotfiles/update.log")" in *"Failed: could not fetch"*) ;; *) exit 1 ;; esac

# A fake transport blocks on a FIFO so concurrency and cancellation are deterministic.
printf '%s\n' '#!/bin/sh
for arg in "$@"; do
    if [ "${INSPECT_FAIL:-}" = "$arg" ]; then exit 1; fi
    if [ "$arg" = fetch ]; then
        [ "$GIT_TERMINAL_PROMPT" = 0 ] && [ "$GCM_INTERACTIVE" = never ] && [ "$GH_PROMPT_DISABLED" = 1 ] || exit 99
        if [ "${FETCH_MODE:-}" = edit ]; then
            printf "edit during fetch\n" >> "$EDIT_FILE"
        elif [ "${FETCH_MODE:-}" = switch ]; then
            "$REAL_GIT" -C "$EDIT_REPO" switch -q -c changed-during-fetch
        elif [ "${FETCH_MODE:-}" = commit ]; then
            "$REAL_GIT" -C "$EDIT_REPO" commit -q --allow-empty -m "test: commit during fetch"
        elif [ "${FETCH_MODE:-}" = block ] || [ "${FETCH_MODE:-}" = resistant ] || [ "${FETCH_MODE:-}" = child-resistant ]; then
            printf "%s\n" "$$" > "$FETCH_ENTERED"
            if [ "${FETCH_MODE:-}" = resistant ]; then trap "" TERM; fi
            if [ "${FETCH_MODE:-}" = resistant ] || [ "${FETCH_MODE:-}" = child-resistant ]; then
                /bin/sh -c '\''trap "" TERM; IFS= read -r release < "$FETCH_FIFO"'\'' &
                printf "%s\n" "$!" > "$FETCH_CHILD"
            fi
            IFS= read -r release < "$FETCH_FIFO"
        fi
    fi
done
exec "$REAL_GIT" "$@"
' > "$root/bin/git"
for tool in sudo brew apt-get; do
    printf '%s\n' '#!/bin/sh' 'printf "unexpected privileged/package call\n" >> "$FORBIDDEN_LOG"' 'exit 99' > "$root/bin/$tool"
done
printf '%s\n' '#!/bin/sh
if [ "$1" = -axo ]; then
    root_pid=$(cat "$FETCH_ENTERED")
    "$REAL_PS" "$@" | awk -v root="$root_pid" '\''$1 == root || $2 == root'\''
    printf "99999999 1 Tue Oct 6 00:00:00 2026\\n99999998 99999999 Tue Oct 6 00:00:00 2026\\n"
    exit 0
fi
if [ "$1" = -p ] && [ "$2" = 99999999 ]; then
    printf "unexpected unrelated process cleanup\\n" >> "$FORBIDDEN_LOG"
    exit 1
fi
exec "$REAL_PS" "$@"
' > "$root/bin/ps"
chmod +x "$root/bin/git" "$root/bin/sudo" "$root/bin/brew" "$root/bin/apt-get" "$root/bin/ps"

wait_for_fetch() {
    attempts=0
    while [ ! -f "$FETCH_ENTERED" ]; do
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 100 ]; then
            printf 'Fetch never started in %s\n' "$case_name" >&2
            for output in "$root/concurrent-first" "$root/interrupted-output" "$root/grace-output"; do
                [ ! -f "$output" ] || cat "$output" >&2
            done
            exit 1
        fi
        sleep 0.05
    done
    if [ -n "${FETCH_CHILD:-}" ]; then
        while [ ! -f "$FETCH_CHILD" ]; do
            attempts=$((attempts + 1))
            [ "$attempts" -lt 100 ] || { printf 'Fetch helper never started\n' >&2; exit 1; }
            sleep 0.05
        done
    fi
}

for inspection in status rev-parse remote; do
    new_checkout "inspection-$inspection"
    before_head=$(git -C "$checkout" rev-parse HEAD)
    if env INSPECT_FAIL="$inspection" PATH="$root/bin:$PATH" XDG_STATE_HOME="$state_home" /bin/sh "$checkout/maintain.sh" update > "$root/inspection-$inspection-output" 2>&1; then
        printf 'Inspection failure should return nonzero\n' >&2
        exit 1
    fi
    assert_eq "$(git -C "$checkout" rev-parse HEAD)" "$before_head"
    [ ! -e "$checkout/.git/FETCH_HEAD" ]
    [ ! -e "$state_home/dotfiles/update.lock" ]
done
new_checkout lock-error
mkdir -p "$state_home/dotfiles"
printf 'not a lock directory\n' > "$state_home/dotfiles/update.lock"
if run_maintain update > "$root/lock-error-output" 2>&1; then
    printf 'Lock creation error should return nonzero\n' >&2
    exit 1
fi
assert_eq "$(cat "$state_home/dotfiles/update.lock")" 'not a lock directory'

case_name=concurrent
checkout="$root/checkouts/$case_name"
state_home="$root/state/$case_name"
FETCH_ENTERED="$root/concurrent-entered"
FETCH_FIFO="$root/concurrent-fifo"
export FETCH_ENTERED FETCH_FIFO
mkfifo "$FETCH_FIFO"
FETCH_MODE=block PATH="$root/bin:$PATH" XDG_STATE_HOME="$state_home" /bin/sh "$checkout/maintain.sh" update > "$root/concurrent-first" 2>&1 &
updater=$!
wait_for_fetch
run_maintain update > "$root/concurrent-second"
case "$(cat "$root/concurrent-second")" in *"another update owns"*) ;; *) exit 1 ;; esac
printf 'release\n' > "$FETCH_FIFO"
wait "$updater"
updater=
assert_eq "$(git -C "$checkout" rev-parse HEAD)" "$latest"
[ ! -e "$state_home/dotfiles/update.lock" ]

case_name=mid-fetch
checkout="$root/checkouts/$case_name"
state_home="$root/state/$case_name"
env FETCH_MODE=edit EDIT_FILE="$checkout/shell/common.sh" PATH="$root/bin:$PATH" XDG_STATE_HOME="$state_home" /bin/sh "$checkout/maintain.sh" update > "$root/mid-fetch-output"
assert_eq "$(git -C "$checkout" rev-parse HEAD)" "$old"
case "$(cat "$checkout/shell/common.sh")" in *"edit during fetch"*) ;; *) exit 1 ;; esac

case_name=switch-fetch
checkout="$root/checkouts/$case_name"
state_home="$root/state/$case_name"
env FETCH_MODE=switch EDIT_REPO="$checkout" PATH="$root/bin:$PATH" XDG_STATE_HOME="$state_home" /bin/sh "$checkout/maintain.sh" update > "$root/switch-fetch-output"
assert_eq "$(git -C "$checkout" branch --show-current)" changed-during-fetch
assert_eq "$(git -C "$checkout" rev-parse HEAD)" "$old"

case_name=head-fetch
checkout="$root/checkouts/$case_name"
state_home="$root/state/$case_name"
env FETCH_MODE=commit EDIT_REPO="$checkout" PATH="$root/bin:$PATH" XDG_STATE_HOME="$state_home" /bin/sh "$checkout/maintain.sh" update > "$root/head-fetch-output"
case "$(cat "$root/head-fetch-output")" in *"HEAD changed during fetch"*) ;; *) exit 1 ;; esac
assert_eq "$(git -C "$checkout" rev-parse HEAD^)" "$old"

case_name=interrupted
checkout="$root/checkouts/$case_name"
state_home="$root/state/$case_name"
FETCH_ENTERED="$root/interrupted-entered"
FETCH_FIFO="$root/interrupted-fifo"
FETCH_CHILD="$root/interrupted-child"
export FETCH_ENTERED FETCH_FIFO FETCH_CHILD
mkfifo "$FETCH_FIFO"
FETCH_MODE=resistant PATH="$root/bin:$PATH" XDG_STATE_HOME="$state_home" /bin/sh "$checkout/maintain.sh" update > "$root/interrupted-output" 2>&1 &
updater=$!
wait_for_fetch
transport=$(cat "$FETCH_ENTERED")
kill -TERM "$updater"
if wait "$updater"; then printf 'Interrupted update should fail\n' >&2; exit 1; fi
updater=
[ ! -e "$state_home/dotfiles/update.lock" ]
if kill -0 "$transport" 2>/dev/null; then printf 'Transport survived cancellation\n' >&2; exit 1; fi
child_state=$(ps -p "$(cat "$FETCH_CHILD")" -o stat= || :)
case "$child_state" in ''|Z*) ;; *) printf 'Helper survived cancellation\n' >&2; exit 1 ;; esac

# Accelerate only the watchdog, not the transport or normal test synchronization.
printf '%s\n' '#!/bin/sh
case "$1" in
    90) exec "$REAL_SLEEP" 0.1;;
    5)
        if [ "${GRACE_TEST:-0}" = 1 ]; then
            printf "ready\\n" > "$GRACE_ENTERED"
            exec "$REAL_SLEEP" 5
        fi
        exec "$REAL_SLEEP" 0.1;;
    *) exec "$REAL_SLEEP" "$@";;
esac
' > "$root/bin/sleep"
chmod +x "$root/bin/sleep"
case_name=timeout
checkout="$root/checkouts/$case_name"
state_home="$root/state/$case_name"
FETCH_ENTERED="$root/timeout-entered"
FETCH_FIFO="$root/timeout-fifo"
FETCH_CHILD="$root/timeout-child"
export FETCH_ENTERED FETCH_FIFO FETCH_CHILD
mkfifo "$FETCH_FIFO"
if env FETCH_MODE=resistant PATH="$root/bin:$PATH" XDG_STATE_HOME="$state_home" /bin/sh "$checkout/maintain.sh" update > "$root/timeout-output" 2>&1; then
    printf 'Timed-out update should fail\n' >&2
    exit 1
fi
[ ! -e "$state_home/dotfiles/update.lock" ]
case "$(cat "$state_home/dotfiles/update.log")" in *"fetch timed out"*) ;; *) exit 1 ;; esac
for process in "$(cat "$FETCH_ENTERED")" "$(cat "$FETCH_CHILD")"; do
    # Orphan zombies have exited and await the OS reaper; they cannot execute.
    process_state=$(ps -p "$process" -o stat= || :)
    case "$process_state" in ''|Z*) ;; *) printf 'Transport/helper survived timeout: %s\n' "$process" >&2; exit 1 ;; esac
done

# Cancel after a TERM-responsive parent exits but its resistant helper is still
# waiting for watchdog escalation. Ownership must survive that transition.
new_checkout grace-cancellation
FETCH_ENTERED="$root/grace-fetch-entered"
FETCH_CHILD="$root/grace-child"
FETCH_FIFO="$root/grace-fifo"
GRACE_ENTERED="$root/grace-entered"
export FETCH_ENTERED FETCH_CHILD FETCH_FIFO GRACE_ENTERED
mkfifo "$FETCH_FIFO"
GRACE_TEST=1 FETCH_MODE=child-resistant PATH="$root/bin:$PATH" XDG_STATE_HOME="$state_home" /bin/sh "$checkout/maintain.sh" update > "$root/grace-output" 2>&1 &
updater=$!
wait_for_fetch
attempts=0
while [ ! -f "$GRACE_ENTERED" ]; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt 100 ] || { printf 'Timeout grace never started\n' >&2; exit 1; }
    sleep 0.05
done
kill -TERM "$updater"
if wait "$updater"; then printf 'Grace cancellation should fail\n' >&2; exit 1; fi
updater=
[ ! -e "$state_home/dotfiles/update.lock" ]
child_state=$(ps -p "$(cat "$FETCH_CHILD")" -o stat= || :)
case "$child_state" in ''|Z*) ;; *) printf 'Helper survived timeout grace cancellation\n' >&2; exit 1 ;; esac

new_checkout controls
run_maintain status > "$root/status-output"
[ ! -e "$state_home" ]
run_maintain enable > "$root/enable-output"
run_maintain disable --dry-run > "$root/disable-preview"
case "$(cat "$SCHEDULER_LOG")" in *"scheduler enable $checkout $state_home/dotfiles"*"scheduler disable $checkout $state_home/dotfiles --dry-run"*) ;; *) exit 1 ;; esac
rm "$SCHEDULER_LOG"
git -C "$checkout" switch -q -c work
run_maintain enable > "$root/work-enable-output"
[ ! -e "$SCHEDULER_LOG" ]
git -C "$checkout" switch -q main
mkdir -p "$state_home/dotfiles/update.lock"
printf '99999999\n' > "$state_home/dotfiles/update.lock/pid"
run_maintain update > "$root/stale-output"
[ -d "$state_home/dotfiles/update.lock" ]
run_maintain status > "$root/stale-status"
case "$(cat "$root/stale-status")" in *"Stale update lock:"*) ;; *) exit 1 ;; esac
rm -rf "$state_home/dotfiles/update.lock"

# Bound logs without dropping errors or rewriting the repository.
awk 'BEGIN { for (i = 0; i < 70000; i++) printf "x" }' > "$state_home/dotfiles/update.log"
run_maintain update > "$root/rotation-output"
[ -f "$state_home/dotfiles/update.log.1" ]
[ "$(wc -c < "$state_home/dotfiles/update.log")" -lt 65536 ]
if run_maintain apply > "$root/invalid-action" 2>&1; then
    printf 'Unknown maintenance action should fail\n' >&2
    exit 1
fi
if XDG_STATE_HOME="$checkout" /bin/sh "$checkout/maintain.sh" update > "$root/inside-state" 2>&1; then
    printf 'State inside the repository should be rejected\n' >&2
    exit 1
fi
[ ! -e "$checkout/dotfiles" ]
ln -s "$checkout" "$root/state-alias"
if XDG_STATE_HOME="$root/state-alias" /bin/sh "$checkout/maintain.sh" update > "$root/symlink-state" 2>&1; then
    printf 'Symlinked state inside the repository should be rejected\n' >&2
    exit 1
fi
[ ! -e "$checkout/dotfiles" ]
if XDG_STATE_HOME=relative /bin/sh "$checkout/maintain.sh" update > "$root/relative-state" 2>&1; then
    printf 'Relative state paths should be rejected\n' >&2
    exit 1
fi

# Updating maintain.sh itself must not execute newly downloaded code in this run.
new_checkout self-update
printf '\nprintf "unexpected self-reload\\n" >> "$FORBIDDEN_LOG"\n' >> "$root/publisher/maintain.sh"
git -C "$root/publisher" add maintain.sh
git -C "$root/publisher" commit -qm 'test: update the maintenance entrypoint'
git -C "$root/publisher" push -q origin main
run_maintain update > "$root/self-update-output"
assert_eq "$(git -C "$checkout" rev-parse HEAD)" "$(git -C "$root/publisher" rev-parse HEAD)"
[ ! -e "$FORBIDDEN_LOG" ]
printf 'Maintenance fast-forward, work protection, concurrency, timeout and control tests passed.\n'
