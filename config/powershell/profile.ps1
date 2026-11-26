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
    if (-not $env:BUN_INSTALL) { $env:BUN_INSTALL = Join-Path $HOME '.bun' }
    $dotfilesPaths += (Join-Path $env:BUN_INSTALL 'bin')
    $dotfilesPaths += (Join-Path $HOME '.opencode\bin')
    $dotfilesPaths += (Join-Path $HOME '.cargo\bin')
    $dotfilesPaths += (Join-Path $HOME 'go\bin')
    $dotfilesPaths += (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
    $env:Path = ((@($dotfilesPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Container }) +
        @($env:Path -split ';')) | Where-Object { $_ } | Select-Object -Unique) -join ';'
    Remove-Variable dotfilesPyenv, dotfilesPaths

    . (Join-Path $PSScriptRoot 'shortcuts.ps1')

    if ($Host.Name -eq 'ConsoleHost' -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) {
        $dotfilesStarship = Get-Command starship.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($dotfilesStarship -and -not (Get-Module PSReadLine)) {
            Import-Module PSReadLine -ErrorAction SilentlyContinue
        }
        # The generated prompt calls this API on every redraw.
        $dotfilesReadLine = 'Microsoft.PowerShell.PSConsoleReadLine' -as [type]
        if ($dotfilesStarship -and $dotfilesReadLine -and $dotfilesReadLine.GetMethod('InViCommandMode', [type[]]@())) {
            # Starship emits UTF-8; Windows PowerShell can use a legacy console code page.
            $dotfilesConsoleEncoding = [Console]::OutputEncoding
            try {
                [Console]::OutputEncoding = [Text.Encoding]::UTF8
                $dotfilesPrompt = & $dotfilesStarship.Source init powershell --print-full-init
            } finally {
                [Console]::OutputEncoding = $dotfilesConsoleEncoding
                Remove-Variable dotfilesConsoleEncoding
            }
            if ($LASTEXITCODE -eq 0 -and $dotfilesPrompt) { Invoke-Expression ($dotfilesPrompt -join "`n") }
            Remove-Variable dotfilesPrompt
        }
        Remove-Variable dotfilesStarship, dotfilesReadLine
    }

    # Keep machine-specific overrides out of the checkout.
    $dotfilesLocalProfile = Join-Path $env:LOCALAPPDATA 'dotfiles\local\profile.ps1'
    if (Test-Path -LiteralPath $dotfilesLocalProfile -PathType Leaf) { . $dotfilesLocalProfile }
    Remove-Variable dotfilesLocalProfile
}
