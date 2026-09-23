# Shared interactive shortcuts for bash and zsh.
alias h='cd "$HOME"'
alias c='clear'
alias ga='git add'
alias gaa='git add .'
alias gpo='git push -u origin'
alias gc='git commit -m'
alias gco='git checkout'
alias gm='git merge'
alias gr='git rebase'
alias gb='git branch'
alias gba='git branch --all'
alias gbd='git branch -D'
alias gcp='git cherry-pick'
alias gd='git diff -w'
alias gu='git reset --soft HEAD~1'
alias gpr='git remote prune origin'
alias ff='git remote prune origin && git pull --ff-only'
alias grd='git fetch origin && git rebase origin/main'
alias gbb='git-switchbranch'
alias grc='git rebase --continue'
alias gra='git rebase --abort'
alias gpf='git push --force-with-lease'
alias ni='npm install'
alias nrb='npm run build'
alias nrd='npm run dev'
alias nrl='npm run lint'
alias ocrc='nvim "$HOME/.config/opencode/opencode.json"'
alias omorc='nvim "$HOME/.config/opencode/oh-my-openagent.json"'

if command -v eza >/dev/null 2>&1; then
    alias l='eza -lah'
else
    alias l='ls -lah'
fi

gs() {
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git status
    elif command -v eza >/dev/null 2>&1; then
        eza
    else
        ls
    fi
}

mc() {
    [ "$#" -eq 1 ] || { printf 'Usage: mc directory\n' >&2; return 2; }
    mkdir -p -- "$1" && cd -- "$1"
}

kps() {
    [ "$#" -gt 0 ] || { printf 'Usage: kps port [port ...]\n' >&2; return 2; }
    for port in "$@"; do
        case "$port" in *[!0-9]*|'') printf 'Invalid port: %s\n' "$port" >&2; return 2 ;; esac
        lsof -nP -t -iTCP:"$port" -sTCP:LISTEN | while IFS= read -r pid; do
            printf 'Stopping listener %s on port %s\n' "$pid" "$port"
            kill -TERM "$pid"
        done
    done
}

# Do not run destructive git restore/reset operations when updating a checkout.
gjcdev() {
    local repo="${GJCDEV_REPO:-$HOME/gjc-upstream-dev}"
    if [ "${1:-}" = update ]; then
        [ "$#" -eq 1 ] || { printf 'Usage: gjcdev update\n' >&2; return 2; }
        (
            cd "$repo" || exit 1
            [ -z "$(git status --porcelain)" ] || { printf 'Development checkout has local changes\n' >&2; exit 1; }
            git switch dev && git pull --ff-only && bun install --frozen-lockfile && bun run build:native
        )
    else
        bun "$repo/packages/coding-agent/src/cli.ts" "$@"
    fi
}
