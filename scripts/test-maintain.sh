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
for name in clean dry dirty staged untracked ignored feature detached diverged concurrent mid-fetch switch-fetch head-fetch interrupted timeout merge-switch merge-capture merge-late merge-concurrent guard-version unguarded; do
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
late_merge=0
for arg in "$@"; do
    if [ "$arg" = version ] && [ "${VERSION_MODE:-}" = old ]; then
        printf "git version 2.27.0\n"
        exit 0
    fi
    if [ "${INSPECT_FAIL:-}" = "$arg" ]; then exit 1; fi
    if [ "$arg" = merge ]; then
        case "${MERGE_MODE:-}" in
            capture) cp -R "$GUARD_SOURCE" "$GUARD_CAPTURE" ;;
            switch) "$REAL_GIT" -C "$EDIT_REPO" switch -q -c switched-during-merge ;;
            late-switch) late_merge=1 ;;
        esac
    fi
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
if [ "${late_merge:-0}" = 1 ]; then
    "$REAL_GIT" "$@"
    status=$?
    if [ "$status" -eq 0 ]; then "$REAL_GIT" -C "$EDIT_REPO" switch -q late-branch; fi
    exit "$status"
fi
# Reuse the generated guard directory through a wrapper hook that also injects
# a competing operation at a deterministic point inside the real merge.
if [ "${MERGE_MODE:-}" = hookwrap ]; then
    case " $* " in
        *" merge "*)
            if [ "$1" = -c ] && [ "${2#core.hooksPath=}" != "$2" ]; then
                shift 2
                set -- -c "core.hooksPath=$WRAP_HOOKS" "$@"
            fi ;;
    esac
fi
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
# An unrelated live PID does not establish that the updater still owns the lock.
printf '%s\n' "$$" > "$state_home/dotfiles/update.lock/pid"
run_maintain status > "$root/live-pid-status"
case "$(cat "$root/live-pid-status")" in *"confirm updater ownership"*) ;; *) exit 1 ;; esac
case "$(cat "$root/live-pid-status")" in *"Update running:"*) exit 1 ;; esac
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
# Missing ancestors followed by '..' must not bypass physical containment checks.
for preview in no yes; do
    if [ "$preview" = yes ]; then set -- --dry-run; else set --; fi
    if XDG_STATE_HOME="$root/nonexistent/../state-alias" /bin/sh "$checkout/maintain.sh" update "$@" > "$root/traversal-state-$preview" 2>&1; then
        printf 'Traversal through a symlink into the repository should be rejected\n' >&2
        exit 1
    fi
    [ ! -e "$checkout/dotfiles" ]
    [ ! -e "$root/nonexistent" ]
done
if XDG_STATE_HOME=relative /bin/sh "$checkout/maintain.sh" update > "$root/relative-state" 2>&1; then
    printf 'Relative state paths should be rejected\n' >&2
    exit 1
fi

# A branch switch between the eligibility check and the checkout must abort before any change.
case_name=merge-switch
checkout="$root/checkouts/$case_name"
state_home="$root/state/$case_name"
env MERGE_MODE=switch EDIT_REPO="$checkout" PATH="$root/bin:$PATH" XDG_STATE_HOME="$state_home" /bin/sh "$checkout/maintain.sh" update > "$root/merge-switch-output" 2>&1
case "$(cat "$root/merge-switch-output")" in *'Skipped: the checkout switched away from main; the checkout is clean at the original commit'*) ;; *) cat "$root/merge-switch-output" >&2; exit 1 ;; esac
assert_eq "$(git -C "$checkout" branch --show-current)" switched-during-merge
assert_eq "$(git -C "$checkout" rev-parse switched-during-merge)" "$old"
assert_eq "$(git -C "$checkout" rev-parse main)" "$old"
assert_eq "$(git -C "$checkout" status --porcelain)" ''
[ ! -e "$checkout/ignored-local.txt" ]
case "$(cat "$checkout/shell/common.sh")" in *fresh*) exit 1 ;; *) ;; esac
[ ! -e "$state_home/dotfiles/update.lock" ]

# The generated hook admits only this fast-forward's transactions.
case_name=merge-capture
checkout="$root/checkouts/$case_name"
state_home="$root/state/$case_name"
env MERGE_MODE=capture GUARD_SOURCE="$state_home/dotfiles/update.lock/ref-guard" GUARD_CAPTURE="$root/ref-guard" PATH="$root/bin:$PATH" XDG_STATE_HOME="$state_home" /bin/sh "$checkout/maintain.sh" update > "$root/merge-capture-output" 2>&1
assert_eq "$(git -C "$checkout" rev-parse HEAD)" "$latest"
[ -x "$root/ref-guard/reference-transaction" ]
[ "$(cut -d' ' -f1 "$root/ref-guard/expected")" = "$old" ]
zeros=$(printf '%*s' "${#old}" '' | tr ' ' 0)
run_guard() {
    rm -f "$root/ref-guard/rejected"
    guard_status=0
    (cd "$checkout" && /bin/sh "$root/ref-guard/reference-transaction" "$1" < "$2") || guard_status=$?
}
printf 'garbage with no refs\n' > "$root/guard-unchecked"
run_guard preparing "$root/guard-unchecked"
assert_eq "$guard_status" 0
[ ! -e "$root/ref-guard/rejected" ]
printf '%s %s ORIG_HEAD\n' "$zeros" "$old" > "$root/guard-orig-ok"
run_guard prepared "$root/guard-orig-ok"
assert_eq "$guard_status" 0
[ ! -e "$root/ref-guard/rejected" ]
printf '%s %s HEAD\n%s %s refs/heads/main\n' "$old" "$latest" "$old" "$latest" > "$root/guard-final-ok"
run_guard prepared "$root/guard-final-ok"
assert_eq "$guard_status" 0
# Empty, duplicate, partial and mixed transaction shapes must fail closed.
: > "$root/guard-empty"
printf '\n' > "$root/guard-blank"
printf '%s %s HEAD\n' "$old" "$latest" > "$root/guard-head-only"
printf '%s %s refs/heads/main\n%s %s refs/heads/main\n' "$old" "$latest" "$old" "$latest" > "$root/guard-duplicate"
printf '%s %s ORIG_HEAD\n%s %s refs/heads/main\n' "$zeros" "$old" "$old" "$latest" > "$root/guard-mixed"
printf '%s %s AUTO_MERGE\n%s %s AUTO_MERGE\n' "$zeros" "$zeros" "$zeros" "$zeros" > "$root/guard-auto-duplicate"
for shape in empty blank head-only duplicate mixed auto-duplicate; do
    run_guard prepared "$root/guard-$shape"
    assert_eq "$guard_status" 1
    assert_eq "$(cat "$root/ref-guard/rejected")" unexpected
done
printf '%s %s refs/heads/main\n' "$old" "$latest" > "$root/guard-main-only"
run_guard prepared "$root/guard-main-only"
assert_eq "$guard_status" 0
printf '%s %s AUTO_MERGE\n' "$zeros" "$zeros" > "$root/guard-auto-merge"
run_guard prepared "$root/guard-auto-merge"
assert_eq "$guard_status" 0
printf '%s %s ORIG_HEAD\n' "$zeros" "$latest" > "$root/guard-orig-stale"
run_guard prepared "$root/guard-orig-stale"
assert_eq "$guard_status" 1
assert_eq "$(cat "$root/ref-guard/rejected")" unexpected
printf '%s %s HEAD\n%s %s refs/heads/other\n' "$old" "$latest" "$old" "$latest" > "$root/guard-foreign-ref"
run_guard prepared "$root/guard-foreign-ref"
assert_eq "$guard_status" 1
assert_eq "$(cat "$root/ref-guard/rejected")" unexpected
printf '%s %s HEAD\n%s %s refs/heads/main\n' "$latest" "$latest" "$old" "$latest" > "$root/guard-stale-old"
run_guard prepared "$root/guard-stale-old"
assert_eq "$guard_status" 1
assert_eq "$(cat "$root/ref-guard/rejected")" unexpected
git -C "$checkout" switch -q -c guard-other "$old"
run_guard prepared "$root/guard-orig-ok"
assert_eq "$guard_status" 1
assert_eq "$(cat "$root/ref-guard/rejected")" branch-switched
run_guard prepared "$root/guard-final-ok"
assert_eq "$guard_status" 1
assert_eq "$(cat "$root/ref-guard/rejected")" commit-race
[ "$guard_status" -ne 0 ]
git -C "$checkout" switch -q main
assert_eq "$(git -C "$checkout" rev-parse guard-other)" "$old"

# A switch after a successful fast-forward is reported instead of passed off as a clean update.
case_name=merge-late
checkout="$root/checkouts/$case_name"
state_home="$root/state/$case_name"
git -C "$checkout" branch late-branch "$old"
if env MERGE_MODE=late-switch EDIT_REPO="$checkout" PATH="$root/bin:$PATH" XDG_STATE_HOME="$state_home" /bin/sh "$checkout/maintain.sh" update > "$root/merge-late-output" 2>&1; then
    printf 'A checkout that left main during the update should be reported\n' >&2
    exit 1
fi
case "$(cat "$root/merge-late-output")" in *'the checkout is no longer main after the update'*) ;; *) cat "$root/merge-late-output" >&2; exit 1 ;; esac
assert_eq "$(git -C "$checkout" rev-parse main)" "$latest"
assert_eq "$(git -C "$checkout" rev-parse late-branch)" "$old"
[ ! -e "$state_home/dotfiles/update.lock" ]

# Git without reference-transaction hooks must not fall back to an unguarded merge.
case_name=guard-version
checkout="$root/checkouts/$case_name"
state_home="$root/state/$case_name"
# A preview must not promise a fast-forward the guard cannot bind.
env VERSION_MODE=old PATH="$root/bin:$PATH" XDG_STATE_HOME="$state_home" /bin/sh "$checkout/maintain.sh" update --dry-run > "$root/guard-version-preview"
case "$(cat "$root/guard-version-preview")" in *'Would skip: Git 2.28 or newer is required'*) ;; *) cat "$root/guard-version-preview" >&2; exit 1 ;; esac
env VERSION_MODE=old PATH="$root/bin:$PATH" XDG_STATE_HOME="$state_home" /bin/sh "$checkout/maintain.sh" update > "$root/guard-version-output" 2>&1
case "$(cat "$root/guard-version-output")" in *'Skipped: Git 2.28 or newer is required'*) ;; *) cat "$root/guard-version-output" >&2; exit 1 ;; esac
assert_eq "$(git -C "$checkout" rev-parse HEAD)" "$old"
[ ! -e "$state_home/dotfiles/update.lock" ]

# An independent mid-merge switch succeeds, but maintenance must fail honestly.
# The rejected ref transaction leaves downloaded index/worktree changes for inspection.
case_name=merge-concurrent
checkout="$root/checkouts/$case_name"
state_home="$root/state/$case_name"
git -C "$checkout" branch mid-race "$old"
wrap_hooks="$root/wrap-hooks"
mkdir -p "$wrap_hooks"
cat > "$wrap_hooks/reference-transaction" <<'HOOK'
#!/bin/sh
cat > "$MID_TX"
if [ "${1:-}" = committed ] && [ ! -f "$MID_ACTED" ] && grep -q ' ORIG_HEAD$' "$MID_TX"; then
    : > "$MID_ACTED"
    # A separate terminal does not inherit the merge invocation hook configuration.
    "$REAL_GIT" -c core.hooksPath=/dev/null -C "$MID_REPO" switch -q mid-race > "$MID_LOG" 2>&1
    printf '%s\n' "$?" > "$MID_STATUS"
fi
exec /bin/sh "$MID_GUARD" "$1" < "$MID_TX"
HOOK
chmod +x "$wrap_hooks/reference-transaction"
MID_TX="$root/mid-tx"
MID_ACTED="$root/mid-acted"
MID_LOG="$root/mid-log"
MID_STATUS="$root/mid-status"
MID_REPO="$checkout"
MID_GUARD="$state_home/dotfiles/update.lock/ref-guard/reference-transaction"
export MID_TX MID_ACTED MID_LOG MID_STATUS MID_REPO MID_GUARD REAL_GIT WRAP_HOOKS="$wrap_hooks"
concurrent_result=0
env MERGE_MODE=hookwrap PATH="$root/bin:$PATH" XDG_STATE_HOME="$state_home" /bin/sh "$checkout/maintain.sh" update > "$root/merge-concurrent-output" 2>&1 || concurrent_result=$?
[ -f "$root/mid-acted" ]
assert_eq "$(cat "$root/mid-status")" 0
assert_eq "$(git -C "$checkout" rev-parse main)" "$old"
assert_eq "$(git -C "$checkout" rev-parse mid-race)" "$old"
assert_eq "$(git -C "$checkout" branch --show-current)" mid-race
[ ! -e "$state_home/dotfiles/update.lock" ]
assert_eq "$concurrent_result" 1
case "$(cat "$root/merge-concurrent-output")" in
    *'Failed:'*'the index and working tree may already hold the fetched changes. Inspect the checkout before continuing.'*) ;;
    *) cat "$root/merge-concurrent-output" >&2; exit 1 ;;
esac
assert_eq "$(git -C "$checkout" diff --cached --name-only)" 'ignored-local.txt
shell/common.sh'
# The staged and working-tree contents are the downloaded tree, not a rollback.
git -C "$checkout" diff --cached --exit-code "$latest" --
git -C "$checkout" diff --exit-code --

# Recover the actual staged residue above, preserving the non-main branch tip.
run_maintain recover > "$root/recovery-preview"
assert_eq "$(git -C "$checkout" branch --show-current)" mid-race
assert_eq "$(git -C "$checkout" diff --cached --name-only)" 'ignored-local.txt
shell/common.sh'
run_maintain recover --discard-changes > "$root/recovery-race"
assert_eq "$(git -C "$checkout" branch --show-current)" main
assert_eq "$(git -C "$checkout" rev-parse mid-race)" "$old"
assert_eq "$(git -C "$checkout" rev-parse main)" "$latest"
assert_eq "$(git -C "$checkout" status --porcelain)" ''
[ ! -e "$state_home/dotfiles/update.lock" ]

for recovery_case in preview dirty clean network untracked ignored locked operation missing-main; do
    new_checkout "recover-$recovery_case"
    git -C "$checkout" reset -q --hard "$old"
    case "$recovery_case" in
        preview|dirty|network) printf 'user tracked edit\n' >> "$checkout/shell/common.sh" ;;
        untracked) printf 'preserve\n' > "$checkout/local.txt" ;;
        ignored) printf 'preserve\n' > "$checkout/ignored-local.txt" ;;
        locked) mkdir -p "$state_home/dotfiles/update.lock"; printf 'owner\n' > "$state_home/dotfiles/update.lock/pid" ;;
        operation) printf '%s\n' "$latest" > "$checkout/.git/MERGE_HEAD" ;;
        missing-main) git -C "$checkout" branch -m work ;;
    esac
    if [ "$recovery_case" = network ]; then git -C "$checkout" remote set-url origin "$root/missing.git"; fi
    saved_status=$(git -C "$checkout" status --porcelain --ignored)
    saved_contents=$(cat "$checkout/shell/common.sh")
    cp "$checkout/.git/index" "$root/recover-index"
    case "$recovery_case" in
        preview)
            run_maintain recover > "$root/recover-preview"
            run_maintain recover --discard-changes --dry-run > "$root/recover-dry"
            cmp "$checkout/.git/index" "$root/recover-index"
            [ ! -e "$checkout/.git/FETCH_HEAD" ]
            [ ! -e "$state_home" ] ;;
        dirty|clean)
            # A clean but divergent main must also be deliberately reset.
            git -C "$checkout" commit -q --allow-empty -m 'local main commit'
            run_maintain recover --discard-changes > "$root/recover-$recovery_case"
            assert_eq "$(git -C "$checkout" rev-parse main)" "$latest"
            assert_eq "$(git -C "$checkout" status --porcelain)" ''
            [ ! -e "$state_home/dotfiles/update.lock" ]
            continue ;;
        *)
            if run_maintain recover --discard-changes > "$root/recover-$recovery_case" 2>&1; then
                printf 'Recovery should refuse %s\n' "$recovery_case" >&2; exit 1
            fi ;;
    esac
    assert_eq "$(git -C "$checkout" rev-parse HEAD)" "$old"
    assert_eq "$(git -C "$checkout" status --porcelain --ignored)" "$saved_status"
    assert_eq "$(cat "$checkout/shell/common.sh")" "$saved_contents"
    case "$recovery_case" in
        untracked) assert_eq "$(cat "$checkout/local.txt")" preserve ;;
        ignored) assert_eq "$(cat "$checkout/ignored-local.txt")" preserve ;;
        locked) assert_eq "$(cat "$state_home/dotfiles/update.lock/pid")" owner ;;
        *) [ ! -e "$state_home/dotfiles/update.lock" ] ;;
    esac
done

# The printed command must work for the actual path, including shell metacharacters.
new_checkout "recover space ' quote"
printf 'edit\n' >> "$checkout/shell/common.sh"
run_maintain update > "$root/recover-command"
command_line=$(sed -n '/^  XDG_STATE_HOME=/p' "$root/recover-command")
[ -n "$command_line" ]
/bin/sh -c "$command_line" > "$root/recover-command-result"
assert_eq "$(git -C "$checkout" status --porcelain)" ''

# Replay must retain the original XDG base when dotfiles itself is a symlink.
new_checkout "recover-state-symlink"
state_destination="$root/recovery-storage"
mkdir -p "$state_home" "$state_destination"
ln -s "$state_destination" "$state_home/dotfiles"
printf 'edit\n' >> "$checkout/shell/common.sh"
run_maintain update > "$root/recover-symlink-command"
command_line=$(sed -n '/^  XDG_STATE_HOME=/p' "$root/recover-symlink-command")
[ -n "$command_line" ]
# The replay must honor an existing lock at the original physical destination.
mkdir "$state_destination/update.lock"
printf 'original owner\n' > "$state_destination/update.lock/pid"
if /bin/sh -c "$command_line" > "$root/recover-symlink-locked" 2>&1; then
    printf 'Replayed recovery must honor the original state lock\n' >&2; exit 1
fi
assert_eq "$(cat "$state_destination/update.lock/pid")" 'original owner'
[ -n "$(git -C "$checkout" status --porcelain)" ]
[ ! -e "$state_destination/dotfiles" ]
rm -rf "$state_destination/update.lock"
/bin/sh -c "$command_line" > "$root/recover-symlink-result"
assert_eq "$(git -C "$checkout" status --porcelain)" ''
case "$(cat "$state_destination/update.log")" in *'Recovered: main -> '*) ;; *) exit 1 ;; esac
[ ! -e "$state_destination/update.lock" ]
[ ! -e "$state_destination/dotfiles" ]
[ -L "$state_home/dotfiles" ]

# A root XDG base stays '/' in guidance; preview must not write there.
XDG_STATE_HOME=/ /bin/sh "$checkout/maintain.sh" recover --dry-run > "$root/recover-root-preview"
command_line=$(sed -n '/^  XDG_STATE_HOME=/p' "$root/recover-root-preview")
case "$command_line" in "  XDG_STATE_HOME='/' /bin/sh "*) ;; *) exit 1 ;; esac

# A merge that bypasses the guard must never be reported as a verified update.
case_name=unguarded
checkout="$root/checkouts/$case_name"
state_home="$root/state/$case_name"
sed 's/git_guarded merge/git_repo merge/' "$root/publisher/maintain.sh" > "$root/unguarded-maintain"
mv "$root/unguarded-maintain" "$root/publisher/maintain.sh"
git -C "$root/publisher" add maintain.sh
git -C "$root/publisher" commit -qm 'test: drop the fast-forward guard'
git -C "$root/publisher" push -q origin main
run_maintain update > "$root/unguarded-first" 2>&1
assert_eq "$(git -C "$checkout" rev-parse HEAD)" "$(git -C "$root/publisher" rev-parse HEAD)"
printf 'alias unguarded=true\n' >> "$root/publisher/shell/common.sh"
git -C "$root/publisher" add shell/common.sh
git -C "$root/publisher" commit -qm 'test: publish another configuration update'
git -C "$root/publisher" push -q origin main
unguarded_latest=$(git -C "$root/publisher" rev-parse HEAD)
if run_maintain update > "$root/unguarded-output" 2>&1; then
    printf 'An unguarded merge must not be reported as a verified update\n' >&2
    exit 1
fi
case "$(cat "$root/unguarded-output")" in *'the fast-forward was not verified by the reference guard'*) ;; *) cat "$root/unguarded-output" >&2; exit 1 ;; esac
assert_eq "$(git -C "$checkout" rev-parse main)" "$unguarded_latest"
[ ! -e "$state_home/dotfiles/update.lock" ]
# Restore the guarded entrypoint for the remaining fixtures.
cp "$repo/maintain.sh" "$root/publisher/maintain.sh"
git -C "$root/publisher" add maintain.sh
git -C "$root/publisher" commit -qm 'test: restore the fast-forward guard'
git -C "$root/publisher" push -q origin main

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
