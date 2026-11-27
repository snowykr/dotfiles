$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Run these tests on Windows.' }

$source = Join-Path (Split-Path -Parent $PSScriptRoot) 'maintain-windows.ps1'
$launcherSource = Join-Path $PSScriptRoot 'run-windows-maintenance.js'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles maintenance & test ' + [guid]::NewGuid().ToString('N'))
$localAppData = $env:LOCALAPPDATA
$oldHome = $env:HOME
$oldXdg = $env:XDG_CONFIG_HOME
$git = (Get-Command git.exe -CommandType Application | Select-Object -First 1).Source

function Git([string] $Repo, [string[]] $Arguments) {
    $output = & $git -C $Repo @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Fixture git $($Arguments[0]) failed: $LASTEXITCODE." }
    $output
}

function Assert-Equal($Actual, $Expected, [string] $Message) {
    if ($Actual -cne $Expected) { throw "$Message (expected '$Expected', got '$Actual')" }
}

function Assert-Match($Output, [string] $Pattern) {
    if (($Output -join "`n") -notmatch $Pattern) { throw "Expected output matching $Pattern; got: $Output" }
}

function Assert-Throws([scriptblock] $Run, [string] $Pattern) {
    try { $null = & $Run } catch {
        Assert-Match $_.Exception.Message $Pattern
        return
    }
    throw "Expected an error matching $Pattern."
}

function Set-File([string] $Repo, [string] $Name, [string] $Text) {
    [IO.File]::WriteAllText((Join-Path $Repo $Name), $Text)
}

# Override only the COM constructor in child script scope. No native scheduler access.
$fakeFolder = [pscustomobject]@{ Task = $null; Registrations = 0; Deletes = 0; Name = ''; Flags = 0; User = ''; Password = $null; LogonType = 0 }
$fakeFolder | Add-Member ScriptMethod GetTask {
    param($Name)
    if ($this.Task -and $this.Name -eq $Name) { return $this.Task }
    throw [Runtime.InteropServices.COMException]::new('Task not found', -2147024894)
}
$fakeFolder | Add-Member ScriptMethod RegisterTask {
    param($Name, $Xml, $Flags, $User, $Password, $LogonType, $Sddl)
    $this.Registrations++
    $this.Name = $Name
    $this.Flags = $Flags
    $this.User = $User
    $this.Password = $Password
    $this.LogonType = $LogonType
    $this.Task = [pscustomobject]@{ Xml = $Xml; Enabled = $true }
    $this.Task
}
$fakeFolder | Add-Member ScriptMethod DeleteTask {
    param($Name, $Flags)
    if ($Name -ne $this.Name) { throw 'Wrong task name.' }
    $this.Deletes++
    $this.Task = $null
}
$fakeService = [pscustomobject]@{ Folder = $fakeFolder }
$fakeService | Add-Member ScriptMethod Connect {}
$fakeService | Add-Member ScriptMethod GetFolder {
    param($Path)
    if ($Path -ne '\') { throw 'Expected the root task folder.' }
    $this.Folder
}
function New-Object([string] $ComObject) {
    if ($ComObject -ne 'Schedule.Service') { throw 'Unexpected COM request.' }
    $fakeService
}

try {
    [void][IO.Directory]::CreateDirectory($tempRoot)
    $env:HOME = $tempRoot
    $env:XDG_CONFIG_HOME = Join-Path $tempRoot 'xdg'
    $env:LOCALAPPDATA = Join-Path $tempRoot 'appdata'
    $state = Join-Path $env:LOCALAPPDATA 'dotfiles\maintenance'
    $upstream = Join-Path $tempRoot 'upstream'
    $checkout = Join-Path $tempRoot 'check out'
    $origin = Join-Path $tempRoot 'origin.git'
    [void][IO.Directory]::CreateDirectory($upstream)
    $null = Git $tempRoot @('init', '--bare', $origin)
    $null = Git $upstream @('init', '-b', 'main')
    $null = Git $upstream @('config', 'user.name', 'Maintenance Test')
    $null = Git $upstream @('config', 'user.email', 'test@example.invalid')
    Copy-Item -LiteralPath $source -Destination $upstream
    $fixtureScripts = Join-Path $upstream 'scripts'
    [void][IO.Directory]::CreateDirectory($fixtureScripts)
    Copy-Item -LiteralPath $launcherSource -Destination $fixtureScripts
    Set-File $upstream '.gitignore' "local.txt`n"
    Set-File $upstream 'tracked.txt' "initial`n"
    $null = Git $upstream @('add', '.')
    $null = Git $upstream @('commit', '-m', 'Initial')
    $null = Git $upstream @('remote', 'add', 'origin', $origin)
    $null = Git $upstream @('push', '-u', 'origin', 'main')
    $null = Git $tempRoot @('clone', '-b', 'main', $origin, $checkout)
    $null = Git $checkout @('config', 'user.name', 'Maintenance Test')
    $null = Git $checkout @('config', 'user.email', 'test@example.invalid')
    $maintain = Join-Path $checkout 'maintain-windows.ps1'
    $launcher = Join-Path $checkout 'scripts\run-windows-maintenance.js'
    $otherMaintain = Join-Path $upstream 'maintain-windows.ps1'
    $initial = Git $checkout @('rev-parse', 'HEAD')

    Set-File $upstream 'tracked.txt' "updated`n"
    $null = Git $upstream @('commit', '-am', 'New version')
    $null = Git $upstream @('push')
    $remote = Git $upstream @('rev-parse', 'HEAD')
    Assert-Match (& $maintain) 'not registered'
    & $maintain -Action update -WhatIf
    & $maintain -Action enable -WhatIf
    Assert-Equal (Git $checkout @('rev-parse', 'origin/main')) $initial 'WhatIf fetched refs'
    Assert-Equal (Test-Path -LiteralPath $state) $false 'Read-only operations created state'
    Assert-Equal $fakeFolder.Registrations 0 'WhatIf registered a task'

    Set-File $checkout 'untracked.txt' 'keep'
    Assert-Match (& $maintain -Action update) 'Skipped: checkout contains local changes'
    Assert-Equal (Git $checkout @('rev-parse', 'origin/main')) $initial 'A dirty checkout fetched refs'
    Remove-Item -LiteralPath (Join-Path $checkout 'untracked.txt')
    Set-File $checkout 'tracked.txt' 'staged change'
    $null = Git $checkout @('add', 'tracked.txt')
    Assert-Match (& $maintain -Action update) 'Skipped: checkout contains local changes'
    $null = Git $checkout @('restore', '--staged', '--worktree', 'tracked.txt')
    $null = Git $checkout @('switch', '-c', 'feature')
    Assert-Match (& $maintain -Action update) 'Skipped: checkout is not on main'
    $null = Git $checkout @('switch', 'main')
    $null = Git $checkout @('config', 'branch.main.merge', 'refs/heads/not-main')
    Assert-Match (& $maintain -Action update) 'Skipped: main does not track origin/main'
    $null = Git $checkout @('config', 'branch.main.merge', 'refs/heads/main')
    Set-File $checkout '.git/CHERRY_PICK_HEAD' $initial
    Assert-Match (& $maintain -Action update) 'a Git operation is in progress'
    Remove-Item -LiteralPath (Join-Path $checkout '.git\CHERRY_PICK_HEAD')
    Assert-Equal (Git $checkout @('rev-parse', 'origin/main')) $initial 'An ineligible checkout fetched refs'

    $held = [IO.File]::Open((Join-Path $state 'maintenance.lock'), 'Open', 'ReadWrite', 'None')
    try {
        Assert-Match (& $maintain -Action update) 'another maintenance run owns the lock'
        Assert-Equal (Git $checkout @('rev-parse', 'origin/main')) $initial 'An overlapping update fetched refs'
    } finally { $held.Dispose() }
    Assert-Match (& $maintain -Action update) '^Updated:'
    Assert-Equal (Git $checkout @('rev-parse', 'HEAD')) $remote 'Clean main did not fast-forward'
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $checkout 'tracked.txt')).Trim()) 'updated' 'Checkout files did not advance'
    Assert-Match (& $maintain -Action update) '^Up to date:'

    Set-File $checkout 'local.txt' 'local ignored content'
    Set-File $upstream 'local.txt' 'remote tracked content'
    $null = Git $upstream @('add', '-f', 'local.txt')
    $null = Git $upstream @('commit', '-m', 'New tracked path')
    $null = Git $upstream @('push')
    Assert-Throws { & $maintain -Action update } 'Git merge failed'
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $checkout 'local.txt'))) 'local ignored content' 'Overwrote an ignored file'
    Assert-Equal (Git $checkout @('rev-parse', 'HEAD')) $remote 'Ignored collision changed HEAD'
    Remove-Item -LiteralPath (Join-Path $checkout 'local.txt')
    Assert-Match (& $maintain -Action update) '^Updated:'

    $null = Git $checkout @('commit', '--allow-empty', '-m', 'Local commit')
    $ahead = Git $checkout @('rev-parse', 'HEAD')
    Assert-Match (& $maintain -Action update) 'ahead of or diverged'
    $null = Git $upstream @('commit', '--allow-empty', '-m', 'Separate remote commit')
    $null = Git $upstream @('push')
    Assert-Match (& $maintain -Action update) 'ahead of or diverged'
    Assert-Equal (Git $checkout @('rev-parse', 'HEAD')) $ahead 'Changed divergent local main'

    $badOrigin = Join-Path $tempRoot 'DO_NOT_LOG_credential-like-sentinel.git'
    $null = Git $checkout @('remote', 'set-url', 'origin', $badOrigin)
    Assert-Throws { & $maintain -Action update } 'Git fetch failed'
    if ([IO.File]::ReadAllText((Join-Path $state 'update.log')) -match 'DO_NOT_LOG') { throw 'Logged an origin URL.' }
    $null = Git $checkout @('remote', 'set-url', 'origin', $origin)

    Assert-Match (& $maintain -Action enable) 'enabled'
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try { $sid = $identity.User.Value } finally { $identity.Dispose() }
    Assert-Equal $fakeFolder.Name "com.snowykr.dotfiles.update.$sid" 'Task is not scoped to this user'
    Assert-Equal $fakeFolder.Flags 0x22 'Task creation could replace an existing task or fire a registration trigger'
    Assert-Equal $fakeFolder.User $sid 'Task registration used another account'
    Assert-Equal $fakeFolder.Password $null 'Task used a password'
    Assert-Equal $fakeFolder.LogonType 3 'Task did not use the interactive token'
    [xml] $definition = $fakeFolder.Task.Xml
    $trigger = $definition.Task.Triggers.TimeTrigger
    Assert-Equal $definition.Task.Triggers.ChildNodes.Count 1 'Expected only a time trigger'
    Assert-Equal $trigger.Repetition.Interval 'PT15M' 'Task interval'
    Assert-Equal $trigger.Repetition.Duration $null 'Repetition is not indefinite'
    $delay = ([DateTimeOffset]::Parse($trigger.StartBoundary) - [DateTimeOffset]::Now).TotalMinutes
    if ($delay -lt 14 -or $delay -gt 15) { throw 'First run should be about 15 minutes after registration.' }
    Assert-Equal $definition.Task.Settings.MultipleInstancesPolicy 'IgnoreNew' 'Overlapping scheduled runs'
    $systemDir = Join-Path ([Environment]::GetFolderPath('Windows')) 'System32'
    $powershell = Join-Path $systemDir 'WindowsPowerShell\v1.0\powershell.exe'
    $wscript = Join-Path $systemDir 'wscript.exe'
    $launcherArguments = '//B //NoLogo //E:JScript "{0}" "{1}" "{2}"'
    Assert-Equal $definition.Task.Actions.Exec.Command $wscript 'Wrong background host'
    Assert-Equal $definition.Task.Actions.Exec.Arguments ($launcherArguments -f $launcher, $powershell, $maintain) 'Wrong task command line'
    Assert-Equal $definition.Task.Actions.Exec.WorkingDirectory $checkout 'Wrong task working directory'
    Assert-Match (& $maintain -Action enable) 'already enabled'
    Assert-Equal $fakeFolder.Registrations 1 'Enable replaced an already enabled task'
    Assert-Throws { & $otherMaintain -Action enable } 'foreign task'
    Assert-Throws { & $otherMaintain -Action disable } 'foreign task'
    $ownedXml = $fakeFolder.Task.Xml
    $fakeFolder.Task.Xml = $ownedXml.Replace('Generated by dotfiles maintain-windows.ps1', 'Unmanaged example')
    Assert-Throws { & $maintain -Action enable } 'unmanaged'
    Assert-Throws { & $maintain -Action disable } 'unmanaged'
    [xml] $legacyTask = $ownedXml
    $legacyTask.Task.Triggers.TimeTrigger.StartBoundary = '2025-01-02T03:04:05Z'
    $legacyExec = $legacyTask.Task.Actions.Exec
    $legacyExec.SelectSingleNode('*[local-name()="Command"]').InnerText = $powershell
    $legacyExec.SelectSingleNode('*[local-name()="Arguments"]').InnerText = '-NoProfile -NonInteractive -File "{0}" -Action update' -f $maintain
    $fakeFolder.Task.Xml = $legacyTask.OuterXml
    Assert-Match (& $maintain -Action status) 'console launcher'
    & $maintain -Action enable -WhatIf
    Assert-Equal $fakeFolder.Registrations 1 'WhatIf migrated a task'
    Assert-Match (& $maintain -Action enable) 'enabled \(background\)'
    Assert-Equal $fakeFolder.Registrations 2 'Enable did not migrate the original task'
    Assert-Equal $fakeFolder.Flags 0x24 'Migration can create a new task or fire a registration trigger'
    [xml] $migrated = $fakeFolder.Task.Xml
    foreach ($section in 'Triggers', 'Principals', 'Settings') {
        Assert-Equal $migrated.Task.$section.OuterXml $legacyTask.Task.$section.OuterXml "Migration changed task $section"
    }
    Assert-Equal $migrated.Task.Actions.OuterXml $definition.Task.Actions.OuterXml 'Wrong migrated action'
    Assert-Match (& $maintain -Action enable) 'already enabled'
    Assert-Equal $fakeFolder.Registrations 2 'Enable migrated the task again'
    & $maintain -Action disable -WhatIf
    Assert-Equal $fakeFolder.Deletes 0 'WhatIf unregistered a task'
    $fakeFolder.Task.Enabled = $false
    Assert-Match (& $maintain -Action enable) 'enabled'
    Assert-Equal $fakeFolder.Flags 0x24 'Enable did not explicitly update the owned disabled task'
    Assert-Match (& $maintain -Action disable) 'not registered'
    & $maintain -Action disable
    Assert-Equal $fakeFolder.Deletes 1 'Disable must unregister only an owned task'

    # Run a disposable probe with the real Windows Script Host.
    $probe = Join-Path $checkout 'probe & exit.ps1'
    Set-File $checkout 'probe & exit.ps1' @'
param([string] $Action)
[IO.File]::WriteAllText((Join-Path (Get-Location).Path 'launcher-result.txt'), $Action)
exit 23
'@
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $wscript
    $start.Arguments = $launcherArguments -f $launcher, $powershell, $probe
    $start.WorkingDirectory = $checkout
    $start.UseShellExecute = $false
    $process = [Diagnostics.Process]::Start($start)
    try {
        if (-not $process.WaitForExit(15000)) {
            $process.Kill()
            throw 'Background launcher did not exit.'
        }
        Assert-Equal $process.ExitCode 23 'Background launcher did not return the child exit code'
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $checkout 'launcher-result.txt'))) 'update' 'Wrong launcher arguments or working directory'
    } finally { $process.Dispose() }

    Write-Output 'Windows maintenance tests passed.'
} finally {
    $env:LOCALAPPDATA = $localAppData
    $env:HOME = $oldHome
    $env:XDG_CONFIG_HOME = $oldXdg
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
