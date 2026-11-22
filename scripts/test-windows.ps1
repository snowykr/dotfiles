$ErrorActionPreference = 'Stop'

$installer = Join-Path (Split-Path -Parent $PSScriptRoot) 'install-windows.ps1'
$options = @{ NoTools = $true; NoGitConfig = $true }
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('dotfiles windows test ' + [guid]::NewGuid().ToString('N'))
$startMarker = '# >>> dotfiles powershell >>>'
$endMarker = '# <<< dotfiles powershell <<<'

try {
    [void][System.IO.Directory]::CreateDirectory($tempRoot)
    $profilePath = Join-Path $tempRoot 'Microsoft.PowerShell_profile.ps1'
    $original = (@('# Existing user profile', '$env:DOTFILES_TEST = ''keep me''', '') -join [Environment]::NewLine)
    [System.IO.File]::WriteAllText($profilePath, $original)

    & $installer @options -ProfilePath $profilePath

    $installed = [System.IO.File]::ReadAllText($profilePath)
    $starts = [regex]::Matches($installed, ('(?m)^' + [regex]::Escape($startMarker) + '\r?$'))
    $ends = [regex]::Matches($installed, ('(?m)^' + [regex]::Escape($endMarker) + '\r?$'))
    if ($starts.Count -ne 1 -or $ends.Count -ne 1 -or $starts[0].Index -ge $ends[0].Index) {
        throw 'Expected exactly one complete dotfiles loader block.'
    }
    $bodyStart = $starts[0].Index + $starts[0].Length
    $body = $installed.Substring($bodyStart, $ends[0].Index - $bodyStart)
    if ($body -cnotmatch 'config[\\/]powershell[\\/]profile\.ps1') {
        throw 'The dotfiles loader does not reference config/powershell/profile.ps1.'
    }
    $blockLength = $ends[0].Index + $ends[0].Length - $starts[0].Index
    $unmanaged = $installed.Remove($starts[0].Index, $blockLength)
    if (-not $unmanaged.Contains($original)) {
        throw 'Installing the loader changed the original profile content.'
    }

    $before = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($profilePath))
    & $installer @options -ProfilePath $profilePath
    if ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($profilePath)) -cne $before) {
        throw 'Reinstalling the loader changed the profile.'
    }

    $missingPath = Join-Path $tempRoot 'missing-profile.ps1'
    & $installer @options -ProfilePath $missingPath -WhatIf
    if (Test-Path -LiteralPath $missingPath) {
        throw 'WhatIf created a profile.'
    }

    $malformedPath = Join-Path $tempRoot 'malformed-profile.ps1'
    [System.IO.File]::WriteAllText($malformedPath, ($original + $startMarker + [Environment]::NewLine))
    $before = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($malformedPath))
    $refused = $false
    try {
        & $installer @options -ProfilePath $malformedPath
    } catch {
        $refused = $true
    }
    if (-not $refused) {
        throw 'The installer did not refuse an unmatched loader marker.'
    }
    if ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($malformedPath)) -cne $before) {
        throw 'The installer modified the profile with an unmatched loader marker.'
    }

    Write-Output 'Windows installer profile tests passed.'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
