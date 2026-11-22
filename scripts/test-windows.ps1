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

    $originalGlobal = $env:GIT_CONFIG_GLOBAL
    $env:GIT_CONFIG_GLOBAL = Join-Path $tempRoot 'gitconfig'
    try {
        git config --global user.name 'Existing Name'
        if ($LASTEXITCODE) { throw 'Could not seed test identity.' }
        git config --global user.email 'snowykr22@gmail.com'
        if ($LASTEXITCODE) { throw 'Could not seed legacy email.' }
        & $installer -NoTools -NoProfile
        if ((git config --global --get user.email) -cne 'jun.koo@snowy.kr' -or
            (git config --global --get user.name) -cne 'Existing Name') { throw 'Identity migration did not preserve the existing name.' }
        git config --global user.email 'custom@example.test'
        if ($LASTEXITCODE) { throw 'Could not seed custom email.' }
        & $installer -NoTools -NoProfile
        if ((git config --global --get user.email) -cne 'custom@example.test') { throw 'Custom Git email was overwritten.' }
    } finally {
        $env:GIT_CONFIG_GLOBAL = $originalGlobal
    }
    $savedLocalAppData = $env:LOCALAPPDATA
    $savedPath = $env:Path
    $env:LOCALAPPDATA = $tempRoot
    try {
        . (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\powershell\profile.ps1')
        if ((Get-Alias gcm).Definition -ne 'Invoke-DotfilesGitCommit' -or
            (Get-Alias gc).Definition -ne 'Get-Content' -or
            (Get-Alias ni).Definition -ne 'New-Item') { throw 'Unexpected PowerShell alias mapping.' }
        Push-Location -LiteralPath $tempRoot
        try {
            mc 'shortcut checkout'
            if ((Get-Location).Path -ne (Join-Path $tempRoot 'shortcut checkout')) { throw 'mc did not change directory.' }
            git init --quiet
            if ($LASTEXITCODE) { throw 'Could not create shortcut test checkout.' }
            git config user.name Test
            git config user.email test@example.test
            [IO.File]::WriteAllText((Join-Path $PWD.Path 'file with spaces.txt'), 'test')
            ga 'file with spaces.txt'
            if ($LASTEXITCODE) { throw 'ga did not stage the file.' }
            gcm 'shortcut commit with spaces'
            if ($LASTEXITCODE -or (git log -1 --format=%s) -cne 'shortcut commit with spaces') { throw 'gcm did not commit.' }
            if (-not ((gs --short --branch) -match '^## ')) { throw 'gs did not forward status arguments.' }
            if ('file with spaces.txt' -notin (la)) { throw 'la did not list file names.' }
        } finally { Pop-Location }
    } finally {
        $env:LOCALAPPDATA = $savedLocalAppData
        $env:Path = $savedPath
    }
    Write-Output 'Windows installer, identity and shortcut tests passed.'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
