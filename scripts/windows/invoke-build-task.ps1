param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-f0-9]{32}$')]
    [string]$BuildId,

    [ValidateSet('Run', 'Stop')]
    [string]$Operation = 'Run',

    [ValidateRange(1, 3600)]
    [int]$LoginTimeoutSeconds = 600,

    [ValidateRange(60, 86400)]
    [int]$BuildTimeoutSeconds = 7200
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot 'build-task-common.ps1')
$paths = Get-PrelisBuildPaths $BuildId
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$scheduler = New-Object -ComObject 'Schedule.Service'
$scheduler.Connect()
$folder = $scheduler.GetFolder('\')
$runnerPath = Join-Path $PSScriptRoot 'run-build-task.ps1'
$powerShellPath = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'

function Get-BuildTask {
    try { return $folder.GetTask($paths.TaskName) }
    catch {
        if ($_.Exception.GetBaseException().HResult -eq -2147024894) { return $null } # HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND)
        throw
    }
}

function Stop-BuildTask {
    $registered = Get-BuildTask
    if ($registered) {
        $principalSid = $registered.Definition.Principal.UserId
        if (-not $principalSid.StartsWith('S-1-')) {
            $principalSid = ([Security.Principal.NTAccount]::new($principalSid)).Translate([Security.Principal.SecurityIdentifier]).Value
        }
        $action = $registered.Definition.Actions.Item(1)
        $expectedArguments = '-File "' + $runnerPath + '" -BuildId ' + $BuildId + ' '
        if ($principalSid -ne $identity.User.Value -or $registered.Definition.Actions.Count -ne 1 -or
            $action.Path -ne $powerShellPath -or -not $action.Arguments.Contains($expectedArguments)) {
            throw 'The task does not belong to this build invocation; refusing to stop it.'
        }
    }
    if (Test-Path -LiteralPath $paths.Worker -PathType Leaf) {
        $worker = Read-PrelisBuildJson $paths.Worker
        if ($worker.BuildId -ne $BuildId -or $worker.UserSid -ne $identity.User.Value -or $worker.SessionId -le 0) {
            throw 'Invalid build worker identity; refusing to stop the process.'
        }
        $process = Get-Process -Id $worker.ProcessId -ErrorAction SilentlyContinue
        if ($process -and $process.StartTime.ToUniversalTime().Ticks.ToString() -eq $worker.StartTimeTicks) {
            if ($process.ProcessName -ne 'powershell' -or $process.SessionId -ne $worker.SessionId) {
                throw 'The worker process does not match this build job.'
            }
            # Stop npm, Cargo, WiX and signing descendants along with the worker.
            $previousPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                $terminationOutput = & (Join-Path $env:SystemRoot 'System32/taskkill.exe') /PID $worker.ProcessId /T /F 2>&1
                $terminationExitCode = $LASTEXITCODE
            }
            finally { $ErrorActionPreference = $previousPreference }
            if ($terminationExitCode -ne 0 -and -not $process.HasExited) {
                throw "Could not stop the build process tree: $terminationOutput"
            }
            if (-not $process.WaitForExit(10000)) { throw 'The build worker did not stop.' }
        }
    }
    if ($registered) {
        if ($registered.GetInstances(0).Count -gt 0) {
            try { $registered.Stop(0) }
            catch { if ($registered.GetInstances(0).Count -gt 0) { throw } }
        }
        $stopDeadline = [DateTime]::UtcNow.AddSeconds(15)
        while ($registered.GetInstances(0).Count -gt 0) {
            if ([DateTime]::UtcNow -gt $stopDeadline) { throw 'The scheduled task did not stop.' }
            Start-Sleep -Milliseconds 250
        }
        $folder.DeleteTask($paths.TaskName, 0)
    }
    Remove-PrelisSigningFiles $paths
    if ((Test-Path -LiteralPath $paths.Directory) -and -not (Test-Path -LiteralPath $paths.Result)) {
        Write-PrelisBuildJson $paths.Result @{
            BuildId = $BuildId; Status = 'Cancelled'; ExitCode = 1
            FinishedAt = [DateTime]::UtcNow.ToString('o'); Error = 'The build was cancelled.'
        }
    }
}

if ($Operation -eq 'Stop') {
    Stop-BuildTask
    exit 0
}

function Wait-GuiSession {
    # WTS queries avoid localized query.exe output and CIM access requirements.
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class PrelisBuildSession {
    [DllImport("wtsapi32.dll", EntryPoint="WTSQuerySessionInformationW", SetLastError=true)]
    public static extern bool Query(IntPtr server, int session, int info, out IntPtr buffer, out int size);
    [DllImport("wtsapi32.dll")]
    public static extern void WTSFreeMemory(IntPtr buffer);
    public static string Read(int session, int info) {
        IntPtr buffer; int size;
        if (!Query(IntPtr.Zero, session, info, out buffer, out size)) return null;
        try { return Marshal.PtrToStringUni(buffer); }
        finally { WTSFreeMemory(buffer); }
    }
}
'@
    [Console]::WriteLine("Waiting for a GUI login as {0} (up to {1} seconds).", $identity.Name, $LoginTimeoutSeconds)
    $deadline = [DateTime]::UtcNow.AddSeconds($LoginTimeoutSeconds)
    do {
        $sessions = @(
            Get-Process explorer -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SessionId -Unique | Where-Object {
                $user = [PrelisBuildSession]::Read($_, 5) # WTSUserName
                $domain = [PrelisBuildSession]::Read($_, 7) # WTSDomainName
                if ($user) {
                    try {
                        $sid = ([Security.Principal.NTAccount]::new($domain, $user)).Translate([Security.Principal.SecurityIdentifier]).Value
                        $sid -eq $identity.User.Value
                    }
                    catch { $false }
                }
            }
        )
        if ($sessions.Count -eq 1) { return [int]$sessions[0] }
        if ($sessions.Count -gt 1) { throw 'Multiple GUI sessions exist for the build user. Keep one session logged on.' }
        if ([DateTime]::UtcNow -ge $deadline) { throw [TimeoutException]::new('Timed out waiting for the build user to log in to the GUI.') }
        Start-Sleep -Seconds 2
    } while ($true)
}

$controllerLock = $null
$jobCreated = $false
$reader = $null
$exitCode = 1
$controllerError = $null
try {
    $controllerLock = [IO.File]::Open((Join-Path $env:USERPROFILE 'prelis-build-controller.lock'),
        [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    New-Item -ItemType Directory -Path $paths.Directory | Out-Null
    $jobCreated = $true
    [IO.File]::WriteAllText($paths.Log, '', [Text.UTF8Encoding]::new($false))
    $sessionId = Wait-GuiSession
    if (-not (Test-Path -LiteralPath $paths.Credential -PathType Leaf)) { throw 'The temporary signing credentials are missing.' }
    $definition = $scheduler.NewTask(0)
    $definition.RegistrationInfo.Description = "Prelis signed Windows build $BuildId"
    $definition.Principal.UserId = $identity.User.Value
    $definition.Principal.LogonType = 3 # TASK_LOGON_INTERACTIVE_TOKEN
    $definition.Principal.RunLevel = 0 # TASK_RUNLEVEL_LUA
    $definition.Settings.Enabled = $true
    $definition.Settings.AllowDemandStart = $true
    $definition.Settings.DisallowStartIfOnBatteries = $false
    $definition.Settings.StopIfGoingOnBatteries = $false
    $definition.Settings.MultipleInstances = 2 # TASK_INSTANCES_IGNORE_NEW
    $definition.Settings.ExecutionTimeLimit = 'PT' + ($BuildTimeoutSeconds + 60) + 'S'
    $action = $definition.Actions.Create(0)
    $action.Path = $powerShellPath
    $action.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $runnerPath +
        '" -BuildId ' + $BuildId + ' -ExpectedUserSid ' + $identity.User.Value + ' -ExpectedSessionId ' + $sessionId
    $action.WorkingDirectory = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $task = $folder.RegisterTaskDefinition($paths.TaskName, $definition, 2, $identity.User.Value, $null, 3, $null)
    $reader = [IO.StreamReader]::new([IO.File]::Open($paths.Log, [IO.FileMode]::Open,
        [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite), [Text.Encoding]::UTF8)
    $instance = $task.RunEx($null, 4, $sessionId, $null) # TASK_RUN_USE_SESSION_ID
    [Console]::WriteLine("Build {0} launched in GUI session {1}.", $BuildId, $sessionId)
    $deadline = [DateTime]::UtcNow.AddSeconds($BuildTimeoutSeconds)
    $launchDeadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        [Console]::Write($reader.ReadToEnd())
        $task = Get-BuildTask
        if (-not $task) { throw 'The build task was removed before completion.' }
        $running = $task.GetInstances(0).Count -gt 0
        if (-not $running -and (Test-Path -LiteralPath $paths.Result)) { break }
        if (-not $running -and [DateTime]::UtcNow -gt $launchDeadline) {
            throw "The task exited without a result file. Task Scheduler result: $($task.LastTaskResult)"
        }
        if ([DateTime]::UtcNow -ge $deadline) { throw [TimeoutException]::new('The Windows build exceeded its time limit.') }
        Start-Sleep -Seconds 1
    } while ($true)
    [Console]::Write($reader.ReadToEnd())
    $result = Read-PrelisBuildJson $paths.Result
    if ($result.BuildId -ne $BuildId -or $result.Status -ne 'Succeeded' -or $result.ExitCode -ne 0 -or
        $result.UserSid -ne $identity.User.Value -or $result.SessionId -ne $sessionId -or $task.LastTaskResult -ne 0) {
        throw "The scheduled build failed: $($result.Error) (Task Scheduler result: $($task.LastTaskResult))"
    }
    $exitCode = 0
}
catch {
    $controllerError = $_.Exception.Message
    [Console]::Error.WriteLine($controllerError)
}
finally {
    if ($jobCreated) {
        try { Stop-BuildTask }
        catch {
            [Console]::Error.WriteLine("Build cleanup failed; temporary files may remain: $($_.Exception.Message)")
            $controllerError = "Build cleanup failed: $($_.Exception.Message)"
            $exitCode = 1
        }
        if ($controllerError) {
            $existing = $null
            if (Test-Path -LiteralPath $paths.Result) {
                try { $existing = Read-PrelisBuildJson $paths.Result }
                catch { [Console]::Error.WriteLine('The existing result JSON is unreadable; recording the controller error.') }
            }
            if (-not $existing -or $existing.Status -ne 'Failed') {
                Write-PrelisBuildJson $paths.Result @{
                    BuildId = $BuildId; Status = 'Failed'; ExitCode = 1
                    FinishedAt = [DateTime]::UtcNow.ToString('o'); Error = $controllerError
                }
            }
        }
    }
    if ($reader) { $reader.Dispose() }
    if ($controllerLock) { $controllerLock.Dispose() }
}
exit $exitCode
