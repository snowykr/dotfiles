[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('update', 'status', 'enable', 'disable')]
    [string] $Action = 'status'
)

$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Run this script on Windows.' }

$repo = [IO.Path]::GetFullPath($PSScriptRoot)
$localAppData = $env:LOCALAPPDATA
if ($localAppData -notmatch '^[A-Za-z]:[\\/]') { throw 'LOCALAPPDATA must be a local absolute path.' }
$state = [IO.Path]::GetFullPath((Join-Path $localAppData 'dotfiles\maintenance'))
if ($state -eq $repo -or $state.StartsWith($repo.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Maintenance state must live outside the checkout.'
}
$log = Join-Path $state 'update.log'
$lockPath = Join-Path $state 'maintenance.lock'
$systemDir = Join-Path ([Environment]::GetFolderPath('Windows')) 'System32'

function Assert-StatePath([string] $Path, [bool] $Directory) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($item -and (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.PSIsContainer -ne $Directory)) {
        throw "Unexpected maintenance state path: $Path"
    }
}

function Assert-StateDirectory {
    # Do not follow directory junctions or symlinks into the checkout.
    for ($dir = $state; $dir; $dir = [IO.Path]::GetDirectoryName($dir)) {
        Assert-StatePath $dir $true
    }
}

function Open-MaintenanceLock {
    Assert-StateDirectory
    [void][IO.Directory]::CreateDirectory($state)
    Assert-StatePath $lockPath $false
    try {
        # File sharing is enforced across session boundaries; termination releases the handle.
        [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
    } catch [IO.IOException] {
        if (($_.Exception.HResult -band 0xffff) -notin 32, 33) { throw }
    }
}

function Write-UpdateResult([string] $Message) {
    [IO.File]::AppendAllText($log, ('{0:o} {1}{2}' -f [DateTimeOffset]::Now, $Message, [Environment]::NewLine))
    Write-Output $Message
}

function Invoke-RepoGit([string[]] $Arguments, [int[]] $Allowed = @(0), [int] $TimeoutSeconds = 30) {
    $gitArgs = @('-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false', '-c', 'core.askPass=',
        '-c', 'credential.interactive=false', '-c', 'submodule.recurse=false', '-C', $repo) + $Arguments
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $gitProgram
    # Windows PowerShell 5.1 does not have ProcessStartInfo.ArgumentList.
    $start.Arguments = ($gitArgs | ForEach-Object { '"' + ($_ -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' }) -join ' '
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    # Use this checkout and the user's ordinary Git config, not inherited repo overrides or tracing.
    foreach ($key in @($start.EnvironmentVariables.Keys)) {
        if ($key -like 'GIT_*' -or $key -eq 'SSH_ASKPASS') { $start.EnvironmentVariables.Remove($key) }
    }
    $start.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    # Use OpenSSH's normal config and agent, not a caller's custom Git SSH wrapper.
    $start.EnvironmentVariables['GIT_SSH_COMMAND'] = 'ssh -o BatchMode=yes'
    $start.EnvironmentVariables['GCM_INTERACTIVE'] = 'never'
    $start.EnvironmentVariables['GH_PROMPT_DISABLED'] = '1'
    $start.EnvironmentVariables['GIT_OPTIONAL_LOCKS'] = '0'
    $process = [Diagnostics.Process]::Start($start)
    try {
        $process.StandardInput.Close()
        $output = $process.StandardOutput.ReadToEndAsync()
        # Never forward raw Git diagnostics: transport/helper errors can contain credential URLs.
        $errors = $process.StandardError.BaseStream.CopyToAsync([IO.Stream]::Null)
        if (-not $process.WaitForExit($TimeoutSeconds * 1000) -or -not $output.Wait(2000) -or -not $errors.Wait(2000)) {
            throw "Git $($Arguments[0]) timed out."
        }
        if ($process.ExitCode -notin $Allowed) {
            throw "Git $($Arguments[0]) failed (exit $($process.ExitCode)); check the checkout and noninteractive origin credentials."
        }
        [pscustomobject]@{ Code = $process.ExitCode; Text = $output.Result.TrimEnd("`r", "`n") }
    } finally {
        try {
            if (-not $process.HasExited) {
                # taskkill covers ordinary Git transport/helper children, not detached processes.
                $PSNativeCommandUseErrorActionPreference = $false
                & (Join-Path $systemDir 'taskkill.exe') /F /T /PID $process.Id *> $null
                if (-not $process.HasExited) { $process.Kill() }
                [void]$process.WaitForExit(5000)
            }
        } finally { $process.Dispose() }
    }
}

function Assert-Checkout {
    $root = (Invoke-RepoGit @('rev-parse', '--show-toplevel')).Text
    if ([IO.Path]::GetFullPath($root) -ne $repo) { throw 'Run the copy at the root of the checkout.' }
}

function Get-Branch {
    (Invoke-RepoGit @('symbolic-ref', '--quiet', 'HEAD') @(0, 1)).Text
}

function Get-HeadCommit {
    (Invoke-RepoGit @('rev-parse', '--verify', 'HEAD^{commit}')).Text
}

function Get-IneligibleReason {
    if ((Get-Branch) -cne 'refs/heads/main') { return 'checkout is not on main' }
    $upstream = (Invoke-RepoGit @('for-each-ref', '--format=%(upstream:remotename) %(upstream:remoteref) %(upstream)', 'refs/heads/main')).Text
    if ($upstream -cne 'origin refs/heads/main refs/remotes/origin/main') { return 'main does not track origin/main' }
}

function Get-DirtyReason {
    if ((Invoke-RepoGit @('status', '--porcelain', '--untracked-files=all', '--ignore-submodules=none')).Text) {
        return 'checkout contains local changes'
    }
    foreach ($name in 'MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'REBASE_HEAD', 'rebase-merge', 'rebase-apply', 'sequencer', 'BISECT_START') {
        $path = (Invoke-RepoGit @('rev-parse', '--git-path', $name)).Text
        if (-not [IO.Path]::IsPathRooted($path)) { $path = Join-Path $repo $path }
        if (Test-Path -LiteralPath $path) { return "a Git operation is in progress ($name)" }
    }
}

function Update-Checkout {
    $reason = Get-IneligibleReason
    if (-not $reason) { $reason = Get-DirtyReason }
    if ($reason) {
        if ($WhatIfPreference) { Write-Output "Would skip: $reason" } else { Write-UpdateResult "Skipped: $reason" }
        return
    }
    if (-not $PSCmdlet.ShouldProcess($repo, 'Fetch origin/main and fast-forward clean main')) { return }
    $before = Get-HeadCommit
    $origin = (Invoke-RepoGit @('remote', 'get-url', 'origin')).Text
    [void](Invoke-RepoGit @('fetch', '--quiet', '--no-tags', '--no-prune', '--no-prune-tags', '--no-recurse-submodules',
        '--no-auto-gc', '--no-write-fetch-head', '--refmap=', 'origin', '+refs/heads/main:refs/remotes/origin/main') -TimeoutSeconds 90)
    $remote = (Invoke-RepoGit @('rev-parse', '--verify', 'refs/remotes/origin/main^{commit}')).Text
    $ancestry = Invoke-RepoGit @('merge-base', '--is-ancestor', $before, $remote) @(0, 1)

    # Deliberately not a lock on interactive Git/editors: there is still a small
    # race between the final checks and merge. Do not switch branches during a run.
    $reason = Get-IneligibleReason
    if (-not $reason) { $reason = Get-DirtyReason }
    if ($reason) { Write-UpdateResult "Skipped after fetch: $reason"; return }
    if ((Invoke-RepoGit @('remote', 'get-url', 'origin')).Text -cne $origin -or (Get-HeadCommit) -cne $before -or
        (Get-Branch) -cne 'refs/heads/main') {
        Write-UpdateResult 'Skipped: checkout refs or origin changed during fetch'
        return
    }
    if ($before -ceq $remote) { Write-UpdateResult "Up to date: $before"; return }
    if ($ancestry.Code -eq 1) { Write-UpdateResult 'Skipped: local main is ahead of or diverged from origin/main'; return }
    [void](Invoke-RepoGit @('merge', '--ff-only', '--no-edit', '--no-autostash', '--no-overwrite-ignore', $remote) -TimeoutSeconds 90)
    if ((Get-Branch) -cne 'refs/heads/main' -or (Get-HeadCommit) -cne $remote) {
        throw 'Checkout changed during the fast-forward; inspect it manually.'
    }
    Write-UpdateResult "Updated: $before -> $remote"
}

function Get-RegisteredTask($Folder) {
    try { $Folder.GetTask($taskName) }
    catch {
        for ($err = $_.Exception; $err; $err = $err.InnerException) {
            if ($err.HResult -eq -2147024894) { return } # HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND)
        }
        throw
    }
}

function Test-OwnedTask($Task) {
    [xml] $definition = $Task.Xml
    $principal = $definition.Task.Principals.Principal
    $actions = $definition.Task.Actions
    if ($definition.Task.RegistrationInfo.Description -cne $marker -or
        $definition.Task.Principals.ChildNodes.Count -ne 1 -or $actions.ChildNodes.Count -ne 1 -or
        $principal.LogonType -cne 'InteractiveToken' -or ($principal.RunLevel -and $principal.RunLevel -cne 'LeastPrivilege') -or
        ($actions.Context -and $actions.Context -cne $principal.id) -or $actions.Exec.Command -ine $shellPath -or
        $actions.Exec.Arguments -cne $taskArguments -or $actions.Exec.WorkingDirectory -ine $repo) {
        return $false
    }
    $owner = $principal.UserId
    if ($owner -ne $sid) {
        try { $owner = [Security.Principal.NTAccount]::new($owner).Translate([Security.Principal.SecurityIdentifier]).Value }
        catch { return $false }
    }
    return $owner -eq $sid
}

function New-TaskXml {
    $firstRun = [DateTime]::UtcNow.AddMinutes(15).ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
    $command = [Security.SecurityElement]::Escape($shellPath)
    $arguments = [Security.SecurityElement]::Escape($taskArguments)
    $directory = [Security.SecurityElement]::Escape($repo)
    # No repetition duration means indefinitely; no login, registration or catch-up trigger.
    @"
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>$marker</Description></RegistrationInfo>
  <Triggers><TimeTrigger><StartBoundary>$firstRun</StartBoundary><Repetition><Interval>PT15M</Interval></Repetition></TimeTrigger></Triggers>
  <Principals><Principal id="Dotfiles"><UserId>$sid</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>false</StartWhenAvailable>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
  </Settings>
  <Actions Context="Dotfiles"><Exec><Command>$command</Command><Arguments>$arguments</Arguments><WorkingDirectory>$directory</WorkingDirectory></Exec></Actions>
</Task>
"@
}

function Invoke-Scheduler {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try { $sid = $identity.User.Value } finally { $identity.Dispose() }
    $taskName = "com.snowykr.dotfiles.update.$sid"
    $marker = 'Generated by dotfiles maintain-windows.ps1'
    $shellPath = Join-Path $systemDir 'WindowsPowerShell\v1.0\powershell.exe'
    $taskArguments = '-NoProfile -NonInteractive -File "{0}" -Action update' -f (Join-Path $repo 'maintain-windows.ps1')
    $scheduler = New-Object -ComObject 'Schedule.Service'
    $scheduler.Connect()
    $folder = $scheduler.GetFolder('\')
    $task = Get-RegisteredTask $folder
    $owned = $task -and (Test-OwnedTask $task)
    if ($Action -eq 'status') {
        $result = if (-not $task) { 'not registered' } elseif (-not $owned) { 'unmanaged or owned by another checkout' }
            elseif ($task.Enabled) { 'enabled' } else { 'disabled' }
        Write-Output "Task \${taskName}: $result"
        return
    }
    if ($task -and -not $owned) { throw "Refusing to change unmanaged or foreign task \$taskName." }
    if ($Action -eq 'disable') {
        # External edits in Task Scheduler do not take our lock. Do not edit this entry concurrently.
        if ($task -and $PSCmdlet.ShouldProcess("\$taskName", 'Unregister update task')) { $folder.DeleteTask($taskName, 0) }
        if (-not $WhatIfPreference) { Write-Output "Task \${taskName}: not registered" }
        return
    }
    if ($task -and $task.Enabled) { Write-Output "Task \${taskName}: already enabled"; return }
    if ($repo.Contains('%') -or $shellPath.Contains('%')) { throw 'Task Scheduler expands environment variables; percent signs in action paths are not supported.' }
    if ($PSCmdlet.ShouldProcess("\$taskName", 'Register interactive update every 15 minutes')) {
        # CREATE (not create-or-update) refuses a racing foreign registration. UPDATE is only for an owned disabled task.
        $flags = if ($task) { 0x24 } else { 0x22 } # Ignore registration triggers, even if added to this definition later.
        [void]$folder.RegisterTask($taskName, (New-TaskXml), $flags, $sid, $null, 3, $null)
        Write-Output "Task \${taskName}: enabled"
    }
}

if ($Action -ne 'disable') {
    $git = Get-Command git.exe -CommandType Application | Select-Object -First 1
    $gitProgram = $git.Source
    Assert-Checkout
}
if ($Action -eq 'status') {
    Write-Output "Repository: $repo"
    $branch = Get-Branch
    if (-not $branch) { $branch = 'detached HEAD' }
    Write-Output "Branch: $branch"
    Write-Output "HEAD: $(Get-HeadCommit)"
    $reason = Get-IneligibleReason
    if (-not $reason) { $reason = Get-DirtyReason }
    if ($reason) { Write-Output "Update would skip: $reason" }
    Invoke-Scheduler
    Assert-StateDirectory
    Assert-StatePath $log $false
    if (Test-Path -LiteralPath $log) {
        Write-Output 'Recent maintenance results:'
        Get-Content -LiteralPath $log -Tail 10
    }
    return
}
if ($Action -eq 'enable') {
    $reason = Get-IneligibleReason
    if ($reason) { throw "Cannot enable updates: $reason." }
}
if ($WhatIfPreference) {
    if ($Action -eq 'update') { Update-Checkout } else { Invoke-Scheduler }
    return
}
$lock = Open-MaintenanceLock
if (-not $lock) {
    if ($Action -eq 'update') { Write-Output 'Skipped: another maintenance run owns the lock'; return }
    throw 'Another maintenance run owns the lock; retry when it finishes.'
}
try {
    if ($Action -eq 'update') {
        Assert-StatePath $log $false
        if ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -ge 65536) {
            Assert-StatePath ($log + '.1') $false
            Move-Item -LiteralPath $log -Destination ($log + '.1') -Force
        }
        try { Update-Checkout }
        catch {
            Write-UpdateResult 'Failed: automatic update could not complete; no reset or stash was attempted.'
            throw
        }
    } else { Invoke-Scheduler }
} finally { $lock.Dispose() }
