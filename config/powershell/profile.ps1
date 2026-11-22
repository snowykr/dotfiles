# Dot-sourced by the current user's PowerShell profile on Windows.
if ($env:OS -eq 'Windows_NT') {
    $dotfilesPyenv = Join-Path $HOME '.pyenv\pyenv-win'
    if (Test-Path -LiteralPath (Join-Path $dotfilesPyenv 'bin\pyenv.bat') -PathType Leaf) {
        if (-not $env:PYENV) { $env:PYENV = $dotfilesPyenv }
        if (-not $env:PYENV_HOME) { $env:PYENV_HOME = $dotfilesPyenv }
        if (-not $env:PYENV_ROOT) { $env:PYENV_ROOT = $dotfilesPyenv }
        $dotfilesPaths = @((Join-Path $dotfilesPyenv 'bin'), (Join-Path $dotfilesPyenv 'shims'))
    } else {
        $dotfilesPaths = @()
    }
    $dotfilesPaths += (Join-Path $HOME '.local\bin')
    $dotfilesPaths += (Join-Path $HOME '.cargo\bin')
    $dotfilesPaths += (Join-Path $HOME 'go\bin')
    $dotfilesPaths += (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
    $env:Path = ((@($dotfilesPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Container }) +
        @($env:Path -split ';')) | Where-Object { $_ } | Select-Object -Unique) -join ';'
    Remove-Variable dotfilesPyenv, dotfilesPaths

    . (Join-Path $PSScriptRoot 'shortcuts.ps1')

    # Keep machine-specific overrides out of the checkout.
    $dotfilesLocalProfile = Join-Path $env:LOCALAPPDATA 'dotfiles\local\profile.ps1'
    if (Test-Path -LiteralPath $dotfilesLocalProfile -PathType Leaf) { . $dotfilesLocalProfile }
    Remove-Variable dotfilesLocalProfile
}
