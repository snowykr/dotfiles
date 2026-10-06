#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
state_dir="${XDG_STATE_HOME:-"$HOME/.local/state"}/dotfiles"
case "$state_dir" in
    /*) ;;
    *) printf 'XDG_STATE_HOME must be an absolute path\n' >&2; exit 2 ;;
esac
# Resolve existing parent symlinks without creating anything, including on previews.
# This also catches /var vs /private/var and symlinked XDG paths into the checkout.
state_parent=$state_dir
state_suffix=
while [ ! -d "$state_parent" ]; do
    if [ -e "$state_parent" ] || [ -L "$state_parent" ]; then
        printf 'Maintenance state path is not a directory: %s\n' "$state_parent" >&2
        exit 2
    fi
    state_suffix="/${state_parent##*/}$state_suffix"
    state_parent=${state_parent%/*}
    [ -n "$state_parent" ] || state_parent=/
done
state_parent=$(CDPATH= cd -- "$state_parent" && pwd -P)
state_dir=$(printf '%s\n' "$state_parent$state_suffix" | awk '
    {
        count = split($0, part, "/"); depth = 0
        for (i = 1; i <= count; i++) {
            if (part[i] == "" || part[i] == ".") continue
            if (part[i] == "..") { if (depth > 0) depth--; continue }
            stack[++depth] = part[i]
        }
        for (i = 1; i <= depth; i++) printf "/%s", stack[i]
        if (depth == 0) printf "/"
        printf "\n"
    }
')
case "$state_dir" in
    "$repo"|"$repo"/*) printf 'Maintenance state must be outside the repository\n' >&2; exit 2 ;;
esac

usage() {
    printf 'Usage: %s [update|status|enable|disable] [--dry-run]\n' "$0"
}

action=${1:-status}
[ "$#" -eq 0 ] || shift
dry_run=0
if [ "$#" -eq 1 ] && [ "$1" = --dry-run ]; then
    dry_run=1
elif [ "$#" -ne 0 ]; then
    usage >&2
    exit 2
fi

# Background work must fail rather than opening authentication prompts.
export GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never GH_PROMPT_DISABLED=1 GIT_OPTIONAL_LOCKS=0

git_repo() {
    git -c core.hooksPath=/dev/null -c core.fsmonitor=false -C "$repo" "$@"
}

rotate_log() {
    file=$1
    if [ -f "$file" ] && [ "$(wc -c < "$file")" -ge 65536 ]; then
        mv "$file" "$file.1"
    fi
}

record() {
    message=$1
    printf '%s\n' "$message"
    printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$message" >> "$state_dir/update.log"
}

eligible_branch() {
    branch_result=0
    branch=$(git_repo symbolic-ref --quiet --short HEAD) || branch_result=$?
    case "$branch_result" in
        0) ;;
        1) branch= ;;
        *) printf 'Failed: could not inspect the checkout branch\n'; return 2 ;;
    esac
    if [ "$branch" != main ]; then
        printf 'Skipped: checkout is %s, not main\n' "${branch:-detached HEAD}"
        return 1
    fi
    if ! git_repo remote get-url origin >/dev/null; then
        printf 'Failed: could not inspect the origin remote\n'
        return 2
    fi
}

clean_checkout() {
    if ! checkout_status=$(git_repo status --porcelain --untracked-files=all); then
        printf 'Failed: could not inspect checkout cleanliness\n'
        return 2
    fi
    if [ -n "$checkout_status" ]; then
        printf 'Skipped: checkout contains local changes\n'
        return 1
    fi
    for operation in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
        if ! operation_path=$(git_repo rev-parse --git-path "$operation"); then
            printf 'Failed: could not inspect in-progress Git operations\n'
            return 2
        fi
        case "$operation_path" in /*) ;; *) operation_path="$repo/$operation_path" ;; esac
        if [ -e "$operation_path" ]; then
            printf 'Skipped: a Git operation is in progress\n'
            return 1
        fi
    done
}

fetch_pid=
watchdog_pid=
lock_dir="$state_dir/update.lock"
capture_fetch_tree() {
    # Include credential/transport descendants before terminating their parent.
    LC_ALL=C ps -axo pid=,ppid=,lstart= | awk -v root="$fetch_pid" '
        { parent[$1] = $2; start[$1] = $3 " " $4 " " $5 " " $6 " " $7 }
        END {
            owned[root] = 1
            do {
                added = 0
                for (pid in parent) {
                    if ((parent[pid] in owned) && owned[parent[pid]] && !(pid in owned)) {
                        owned[pid] = 1; added = 1
                    }
                }
            } while (added)
            for (pid in owned) if (owned[pid] && start[pid] != "") print pid "|" start[pid]
        }
    '
}

signal_fetch_tree() {
    signal=$1 targets=$2
    while IFS='|' read -r target started; do
        # Do not signal a different process if a recorded PID has been reused.
        current_start=$(LC_ALL=C ps -p "$target" -o lstart= | awk '{$1=$1; print}')
        if [ "$current_start" = "$started" ]; then
            kill "-$signal" "$target" 2>/dev/null || :
        fi
    done < "$targets"
}

fetch_tree_alive() {
    while IFS='|' read -r target started; do
        current_start=$(LC_ALL=C ps -p "$target" -o lstart= | awk '{$1=$1; print}')
        if [ "$current_start" = "$started" ]; then return 0; fi
    done < "$1"
    return 1
}

cleanup_update() {
    if [ -n "$watchdog_pid" ] && kill -0 "$watchdog_pid" 2>/dev/null; then
        kill -TERM "$watchdog_pid"
        wait "$watchdog_pid" || :
    fi
    if [ -n "$fetch_pid" ]; then
        capture_fetch_tree > "$lock_dir/cleanup.targets"
        if [ -f "$lock_dir/watchdog.targets" ]; then
            cat "$lock_dir/watchdog.targets" >> "$lock_dir/cleanup.targets"
        fi
        signal_fetch_tree TERM "$lock_dir/cleanup.targets"
        if fetch_tree_alive "$lock_dir/cleanup.targets"; then
            sleep 5
            signal_fetch_tree KILL "$lock_dir/cleanup.targets"
        fi
        wait "$fetch_pid" || :
    fi
    rm -rf "$lock_dir"
}

fetch_remote() {
    # Bound noninteractive transport and credential helpers as well as Git itself.
    git -c core.hooksPath=/dev/null -c core.fsmonitor=false \
        -c credential.interactive=false -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 \
        -C "$repo" fetch --quiet --no-tags origin \
        '+refs/heads/main:refs/remotes/origin/main' > "$lock_dir/fetch.log" 2>&1 &
    fetch_pid=$!
    (
        sleeper=
        trap 'if [ -n "$sleeper" ] && kill -0 "$sleeper" 2>/dev/null; then kill "$sleeper"; fi; exit 0' TERM INT HUP
        sleep 90 &
        sleeper=$!
        wait "$sleeper"
        if kill -0 "$fetch_pid" 2>/dev/null; then
            printf 'Fetch timed out after 90 seconds\n' > "$lock_dir/timeout"
            capture_fetch_tree > "$lock_dir/watchdog.targets"
            signal_fetch_tree TERM "$lock_dir/watchdog.targets"
            sleep 5 &
            sleeper=$!
            wait "$sleeper"
            signal_fetch_tree KILL "$lock_dir/watchdog.targets"
        fi
    ) &
    watchdog_pid=$!
    result=0
    wait "$fetch_pid" || result=$?
    # Keep ownership until descendant escalation has also completed.
    # Let timeout escalation finish even if Git exits before a helper does.
    if [ ! -f "$lock_dir/timeout" ] && kill -0 "$watchdog_pid" 2>/dev/null; then kill -TERM "$watchdog_pid"; fi
    wait "$watchdog_pid" || :
    watchdog_pid=
    fetch_pid=
    if [ -f "$lock_dir/timeout" ]; then
        record 'Failed: fetch timed out after 90 seconds'
        return 1
    fi
    if [ "$result" -ne 0 ]; then
        record 'Failed: could not fetch origin/main; check network and noninteractive Git credentials'
        tail -c 16384 "$lock_dir/fetch.log" | tee -a "$state_dir/update.log"
        return 1
    fi
}

update() {
    # A dry run is strictly read-only, including refs, logs and scheduler state.
    if [ "$dry_run" -eq 1 ]; then
        inspection_result=0
        eligible_branch && clean_checkout || inspection_result=$?
        case "$inspection_result" in 0) ;; 1) return 0 ;; *) return 1 ;; esac
        printf 'Would fetch origin/main and fast-forward this clean main checkout\n'
        return
    fi

    mkdir -p "$state_dir"
    if lock_error=$(mkdir "$lock_dir" 2>&1); then
        :
    elif [ -d "$lock_dir" ]; then
        printf 'Skipped: another update owns %s; see maintain.sh status\n' "$lock_dir"
        return 0
    else
        record "Failed: could not create update lock: $lock_error"
        return 1
    fi
    trap cleanup_update EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    printf '%s\n' "$$" > "$lock_dir/pid"
    rotate_log "$state_dir/update.log"
    rotate_log "$state_dir/scheduler.log"

    inspection_result=0
    reason=$(eligible_branch && clean_checkout) || inspection_result=$?
    if [ "$inspection_result" -ne 0 ]; then
        record "$reason"
        [ "$inspection_result" -eq 1 ] && return 0
        return 1
    fi
    before=$(git_repo rev-parse HEAD)
    fetch_remote || return 1
    # Fetch can take time: re-check user edits, branch switches and local commits.
    inspection_result=0
    reason=$(eligible_branch && clean_checkout) || inspection_result=$?
    if [ "$inspection_result" -ne 0 ]; then
        record "$reason"
        [ "$inspection_result" -eq 1 ] && return 0
        return 1
    fi
    if [ "$(git_repo rev-parse HEAD)" != "$before" ]; then
        record 'Skipped: HEAD changed during fetch'
        return 0
    fi
    remote=$(git_repo rev-parse refs/remotes/origin/main)
    if [ "$before" = "$remote" ]; then record "Up to date: $before"; return 0; fi
    ancestry=0
    git_repo merge-base --is-ancestor "$before" "$remote" || ancestry=$?
    case "$ancestry" in
        0) ;;
        1) record 'Skipped: local main is ahead or diverged from origin/main'; return 0 ;;
        *) record 'Failed: could not compare local and remote history'; return 1 ;;
    esac
    if git_repo merge --ff-only --no-edit --no-overwrite-ignore "$remote" > "$lock_dir/merge.log" 2>&1; then
        record "Updated: $before -> $remote"
        printf 'Open a new shell or reload app settings to use updated configuration.\n'
    else
        record 'Failed: fast-forward was rejected; local work was not reset or stashed'
        tail -c 16384 "$lock_dir/merge.log" | tee -a "$state_dir/update.log"
        return 1
    fi
}

status() {
    printf 'Repository: %s\n' "$repo"
    printf 'Branch: %s\n' "$(git_repo symbolic-ref --quiet --short HEAD || printf 'detached HEAD')"
    git_repo status --short
    printf 'HEAD: %s\n' "$(git_repo rev-parse HEAD)"
    if git_repo rev-parse --verify refs/remotes/origin/main >/dev/null 2>&1; then
        printf 'Local/remote-only commits (cached origin/main): '
        git_repo rev-list --left-right --count HEAD...refs/remotes/origin/main
    fi
    if [ -d "$lock_dir" ]; then
        owner=$(cat "$lock_dir/pid" 2>/dev/null || :)
        case "$owner" in
            ''|*[!0-9]*) printf 'Update lock has no valid owner: %s\n' "$lock_dir" ;;
            *)
                if kill -0 "$owner" 2>/dev/null; then
                    printf 'Update running: PID %s\n' "$owner"
                else
                    printf 'Stale update lock: %s (PID %s no longer exists)\n' "$lock_dir" "$owner"
                    printf 'Remove this lock directory after confirming no update is running.\n'
                fi ;;
        esac
    fi
    /bin/sh "$repo/scripts/scheduler.sh" status "$repo" "$state_dir"
    if [ -f "$state_dir/update.log" ]; then
        printf '\nRecent maintenance results:\n'
        tail -n 10 "$state_dir/update.log"
    fi
}

# All functions and this dispatch are parsed before update may replace this file.
case "$action" in
    update) update ;;
    status) status ;;
    enable)
        eligibility=0
        eligible_branch || eligibility=$?
        if [ "$eligibility" -gt 1 ]; then exit 1; fi
        if [ "$eligibility" -eq 0 ]; then
            if [ "$dry_run" -eq 1 ]; then
                /bin/sh "$repo/scripts/scheduler.sh" enable "$repo" "$state_dir" --dry-run
            else
                /bin/sh "$repo/scripts/scheduler.sh" enable "$repo" "$state_dir"
            fi
        fi ;;
    disable)
        if [ "$dry_run" -eq 1 ]; then
            /bin/sh "$repo/scripts/scheduler.sh" disable "$repo" "$state_dir" --dry-run
        else
            /bin/sh "$repo/scripts/scheduler.sh" disable "$repo" "$state_dir"
        fi ;;
    -h|--help) usage ;;
    *) usage >&2; exit 2 ;;
esac
