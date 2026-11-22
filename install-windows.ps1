[CmdletBinding(SupportsShouldProcess)]
param(
    [switch] $NoTools,
    [switch] $NoGitConfig,
    [switch] $NoProfile,
    [string] $ProfilePath = $PROFILE.CurrentUserAllHosts
)

$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Run this installer on Windows.' }

function Find-Tool([string] $Name) {
    Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Invoke-Checked([string] $Program, [string[]] $Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program exited with code $LASTEXITCODE." }
}

function Refresh-ToolPath {
    # Installers can update PATH in the registry without updating this process.
    $paths = @($env:Path -split ';')
    foreach ($scope in 'Machine', 'User') {
        $paths += [Environment]::GetEnvironmentVariable('Path', $scope) -split ';'
    }
    $paths += (Join-Path $HOME '.cargo\bin')
    $paths += (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
    $env:Path = ($paths | Where-Object { $_ } | Select-Object -Unique) -join ';'
}

function Install-WingetTool([string] $Command, [string] $Id, [string[]] $Extra = @()) {
    if (Find-Tool $Command) { return }
    if (-not $PSCmdlet.ShouldProcess($Id, 'Install from the winget source')) { return }
    $winget = Find-Tool 'winget.exe'
    if (-not $winget) { throw 'WinGet is missing. Install Microsoft App Installer or use -NoTools.' }
    Invoke-Checked $winget.Source (@('install', '--id', $Id, '--exact', '--source', 'winget',
        '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity', '--silent') + $Extra)
    Refresh-ToolPath
    if (-not (Find-Tool $Command)) { throw "$Id installed, but $Command was not found. Open a new session and rerun setup." }
}

# Validate the profile before installing tools or writing Git settings.
if (-not $NoProfile) {
    if ($ProfilePath -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\]+\\[^\\]+\\)') { throw 'ProfilePath must be an absolute Windows path.' }
    $ProfilePath = [IO.Path]::GetFullPath($ProfilePath)
    $relativeToRepo = $PSScriptRoot.TrimEnd('\') + '\'
    if ($ProfilePath.StartsWith($relativeToRepo, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The user profile must live outside the dotfiles checkout.'
    }
    $start = '# >>> dotfiles powershell >>>'
    $end = '# <<< dotfiles powershell <<<'
    $managed = (Join-Path $PSScriptRoot 'config\powershell\profile.ps1').Replace("'", "''")
    $loader = ". '$managed'"
    $existing = ''
    $encoding = New-Object Text.UTF8Encoding($true, $true)
    $profileExists = Test-Path -LiteralPath $ProfilePath
    if ($profileExists) {
        $item = Get-Item -LiteralPath $ProfilePath -Force
        if ($item.PSIsContainer -or $item.LinkType) { throw "Not a regular profile file: $ProfilePath" }
        $reader = New-Object IO.StreamReader($ProfilePath, $encoding, $true)
        try { $existing = $reader.ReadToEnd(); $encoding = $reader.CurrentEncoding }
        finally { $reader.Dispose() }
    }
    $markers = @($existing -split '\r?\n' | Where-Object { $_ -match '^\s*#\s*(>>>|<<<)\s*dotfiles powershell' })
    $newline = if ($existing.Contains("`r`n") -or -not $existing.Contains("`n")) { "`r`n" } else { "`n" }
    $block = $start, $loader, $end -join $newline
    if ($markers.Count -ne 0 -and ($markers.Count -ne 2 -or $existing -cnotmatch ('(?m)^' + [regex]::Escape($block) + '\r?$'))) {
        throw "Malformed or conflicting dotfiles block in $ProfilePath. Review it before rerunning setup."
    }
}

if (-not $WhatIfPreference) { Refresh-ToolPath }
if (-not $NoTools) {
    Install-WingetTool 'git.exe' 'Git.Git'
    Install-WingetTool 'gh.exe' 'GitHub.cli'
    Install-WingetTool 'uv.exe' 'astral-sh.uv'
    Install-WingetTool 'go.exe' 'GoLang.Go'
    Install-WingetTool 'rustup.exe' 'Rustlang.Rustup' @('--override', '-y --default-toolchain stable --profile minimal')

    $pyenvRoot = Join-Path $HOME '.pyenv'
    $pyenv = Join-Path $pyenvRoot 'pyenv-win\bin\pyenv.bat'
    if (-not (Find-Tool 'pyenv.bat') -and -not (Test-Path -LiteralPath $pyenv -PathType Leaf)) {
        if (Test-Path -LiteralPath $pyenvRoot) { throw "Existing $pyenvRoot is not a recognized pyenv-win installation; leaving it intact." }
        if ($PSCmdlet.ShouldProcess($pyenvRoot, 'Clone pyenv-win from its official GitHub repository')) {
            $git = Find-Tool 'git.exe'
            Invoke-Checked $git.Source @('clone', '--depth', '1', 'https://github.com/pyenv-win/pyenv-win.git', $pyenvRoot)
            Invoke-Checked $pyenv @('--version')
        }
    }

    if (-not (Find-Tool 'nvm.exe')) {
        $node = Find-Tool 'node.exe'
        if ($node) {
            Write-Warning "Node already exists at $($node.Source); leaving it in place. Migrate standalone Node before installing NVM for Windows."
        } else {
            Install-WingetTool 'nvm.exe' 'CoreyButler.NVMforWindows'
        }
    }
}

if (-not $NoGitConfig) {
    $git = Find-Tool 'git.exe'
    if (-not $git) {
        if (-not $WhatIfPreference) { throw 'Git is missing. Install it or pass -NoGitConfig.' }
    }
    foreach ($setting in @(@('user.name', 'snowykr'), @('user.email', 'jun.koo@snowy.kr'))) {
        $key, $value = $setting
        if ($git) {
            $current = & $git.Source config --global --get $key
            if ($LASTEXITCODE -eq 0 -and $current -and
                -not ($key -eq 'user.email' -and $current -eq 'snowykr22@gmail.com')) { continue }
            if ($LASTEXITCODE -notin 0, 1) { throw "Could not read Git setting $key." }
        }
        if ($PSCmdlet.ShouldProcess($key, "Set Git identity to $value")) {
            Invoke-Checked $git.Source @('config', '--global', $key, $value)
        }
    }
}

if (-not $NoProfile -and $markers.Count -eq 0 -and $PSCmdlet.ShouldProcess($ProfilePath, 'Install PowerShell profile loader')) {
    $directory = Split-Path -Parent $ProfilePath
    [void][IO.Directory]::CreateDirectory($directory)
    $prefix = $existing
    if ($prefix -and -not $prefix.EndsWith("`n")) { $prefix += $newline }
    $profileText = $prefix + $block + $newline
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseInput($profileText, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw "Cannot append a loader to an invalid PowerShell profile: $ProfilePath" }
    # Write alongside the profile, keeping a backup when replacing an existing file.
    $temporary = Join-Path $directory ('.dotfiles-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporary, $profileText, $encoding)
        if ($profileExists) {
            if ([IO.File]::ReadAllText($ProfilePath, $encoding) -cne $existing) { throw 'Profile changed during installation. Rerun setup.' }
            [IO.File]::Replace($temporary, $ProfilePath, "$temporary.bak")
        } else {
            [IO.File]::Move($temporary, $ProfilePath)
        }
    } finally {
        [IO.File]::Delete($temporary)
    }
}
