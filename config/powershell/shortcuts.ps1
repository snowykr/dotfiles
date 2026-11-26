# Shared shell shortcuts, adapted to native Windows PowerShell.
function Set-DotfilesHome { Set-Location -LiteralPath $HOME }
# Match Bash and Zsh; spell out Get-History for the PowerShell command.
Set-Alias -Name h -Value Set-DotfilesHome -Option AllScope -Force
function hr { herdr @args }
function c { Clear-Host }

function ga { git add @args }
function gaa { git add . @args }
function gpo { git push -u origin @args }
function Invoke-DotfilesGitCommit { git commit -m @args }
# gcm is explicitly reserved for Git commit here; Get-Command still works.
Set-Alias -Name gcm -Value Invoke-DotfilesGitCommit -Option AllScope,ReadOnly -Force
function gco { git checkout @args }
function gmg { git merge @args }
function gr { git rebase @args }
function gb { git branch @args }
function gba { git branch --all @args }
function gbd { git branch -D @args }
function gcp { git cherry-pick @args }
function gd { git diff -w @args }
function gundo { git reset --soft 'HEAD~1' @args }
function gpr { git remote prune origin @args }
function ff {
    git remote prune origin
    if ($LASTEXITCODE -eq 0) { git pull --ff-only @args }
}
function grd {
    git fetch origin
    if ($LASTEXITCODE -eq 0) { git rebase origin/main @args }
}
function gbb {
    if (Get-Command git-switchbranch -ErrorAction SilentlyContinue) { git-switchbranch @args }
    else { git switch @args }
}
function grc { git rebase --continue @args }
function gra { git rebase --abort @args }
function gpf { git push --force-with-lease @args }

# Invoke npm.cmd rather than npm.ps1 so execution policy does not block npm.
function npi { npm.cmd install @args }
function nrb { npm.cmd run build @args }
function nrd { npm.cmd run dev @args }
function nrl { npm.cmd run lint @args }

function Invoke-DotfilesEditor([string] $FilePath) {
    foreach ($name in 'nvim.exe', 'vim.exe', 'edit.exe') {
        $editor = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($editor) { & $editor.Source $FilePath; return }
    }
    $git = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($git) {
        $bundledVim = Join-Path (Split-Path -Parent (Split-Path -Parent $git.Source)) 'usr\bin\vim.exe'
        if (Test-Path -LiteralPath $bundledVim -PathType Leaf) { & $bundledVim $FilePath; return }
    }
    throw 'No terminal editor found. Install Neovim, Vim, or Microsoft Edit.'
}
function rc { Invoke-DotfilesEditor $PROFILE.CurrentUserAllHosts }
function s {
    $env:Path = @(
        [Environment]::GetEnvironmentVariable('Path', 'Machine')
        [Environment]::GetEnvironmentVariable('Path', 'User')
    ) -join ';'
    . $PROFILE.CurrentUserAllHosts
}

function l {
    if (Get-Command eza -ErrorAction SilentlyContinue) { if (-not $args.Count) { $args = @('.') }; eza -lah @args }
    else { Get-ChildItem -Force @args }
}
function gs {
    # Windows PowerShell can turn redirected native stderr into a terminating error.
    $ErrorActionPreference = 'Continue'
    $inWorkTree = git rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -eq 0 -and $inWorkTree -eq 'true') { git status @args }
    elseif (Get-Command eza -ErrorAction SilentlyContinue) { if (-not $args.Count) { $args = @('.') }; eza @args }
    else { Get-ChildItem @args }
}
function mc {
    param([Parameter(Mandatory)][string] $Directory)
    if ($args.Count) { throw 'Usage: mc directory' }
    [void][IO.Directory]::CreateDirectory($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Directory))
    Set-Location -LiteralPath $Directory
}
function kps {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory, Position=0, ValueFromRemainingArguments)][ValidateRange(1, 65535)][int[]] $Port)
    $owners = Get-NetTCPConnection -State Listen -ErrorAction Stop |
        Where-Object { $_.LocalPort -in $Port } | Select-Object -ExpandProperty OwningProcess -Unique
    foreach ($owner in $owners) {
        if ($owner -eq $PID) { Write-Warning 'Skipping the current PowerShell process.'; continue }
        if ($PSCmdlet.ShouldProcess("PID $owner", 'Stop TCP listener')) { Stop-Process -Id $owner }
    }
}

function gjcdev {
    $repo = if ($env:GJCDEV_REPO) { $env:GJCDEV_REPO } else { Join-Path $HOME 'gjc-upstream-dev' }
    if ($args.Count -and $args[0] -ceq 'update') {
        if ($args.Count -ne 1) { throw 'Usage: gjcdev update' }
        Push-Location -LiteralPath $repo -ErrorAction Stop
        try {
            $changes = git status --porcelain
            if ($LASTEXITCODE -ne 0 -or $changes) { throw 'Development checkout has local changes or is not readable.' }
            git switch dev
            if ($LASTEXITCODE -ne 0) { return }
            git pull --ff-only
            if ($LASTEXITCODE -ne 0) { return }
            bun install --frozen-lockfile
            if ($LASTEXITCODE -eq 0) { bun run build:native }
        } finally { Pop-Location }
    } else {
        bun (Join-Path $repo 'packages\coding-agent\src\cli.ts') @args
    }
}
