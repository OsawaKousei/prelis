param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-f0-9]{32}$')]
    [string]$BuildId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^S-1-[0-9-]+$')]
    [string]$ExpectedUserSid,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 2147483647)]
    [int]$ExpectedSessionId
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot 'build-task-common.ps1')
$paths = Get-PrelisBuildPaths $BuildId
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$workerProcess = Get-Process -Id $PID
$writer = $null
$workerLock = $null
$secret = ''
$exitCode = 1
$result = [ordered]@{
    BuildId = $BuildId
    Status = 'Failed'
    ExitCode = 1
    UserSid = $identity.User.Value
    SessionId = $workerProcess.SessionId
    StartedAt = [DateTime]::UtcNow.ToString('o')
    FinishedAt = $null
    Error = $null
}

function Write-BuildLog {
    param([string]$Message)
    if ($secret) { $Message = $Message.Replace($secret, '[redacted]') }
    if ($writer) {
        $writer.WriteLine($Message)
        $writer.Flush()
    }
}

try {
    if (-not (Test-Path -LiteralPath $paths.Directory -PathType Container)) {
        throw 'The build job directory was not prepared by invoke-build-task.ps1.'
    }
    # Record this PowerShell process before starting any build subprocesses.
    Write-PrelisBuildJson $paths.Worker @{
        BuildId = $BuildId
        UserSid = $identity.User.Value
        ProcessId = $PID
        StartTimeTicks = $workerProcess.StartTime.ToUniversalTime().Ticks.ToString()
        SessionId = $workerProcess.SessionId
    }
    $logStream = [IO.File]::Open($paths.Log, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
    $writer = [IO.StreamWriter]::new($logStream, [Text.UTF8Encoding]::new($false))
    if ($identity.User.Value -ne $ExpectedUserSid -or
        $workerProcess.SessionId -ne $ExpectedSessionId -or -not [Environment]::UserInteractive) {
        throw 'The build task is not running as the requested user in the requested GUI session.'
    }
    # This lock remains held even if the initiating SSH connection disappears.
    $workerLock = [IO.File]::Open((Join-Path $env:USERPROFILE 'prelis-build-worker.lock'),
        [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    if (Test-Path -LiteralPath $paths.Credential -PathType Leaf) {
        foreach ($line in [IO.File]::ReadAllLines($paths.Credential, [Text.Encoding]::UTF8)) {
            if ($line.StartsWith('AZURE_CLIENT_SECRET=')) { $secret = $line.Substring(20) }
        }
    }
    Write-BuildLog "Build $BuildId started in GUI session $ExpectedSessionId."
    & (Join-Path $PSScriptRoot 'build.ps1') -CredentialFile $paths.CredentialFile `
        -CompletionFile $paths.CompletionFile -BuildId $BuildId *>&1 |
        Out-String -Stream -Width 240 | ForEach-Object { Write-BuildLog $_ }
    if (-not (Test-Path -LiteralPath $paths.Completion -PathType Leaf)) {
        throw 'The build returned without the signed-build completion marker.'
    }
    $result.Status = 'Succeeded'
    $result.ExitCode = 0
    $exitCode = 0
}
catch {
    $message = $_.Exception.Message
    if ($secret) { $message = $message.Replace($secret, '[redacted]') }
    $result.Error = $message
    $result['ErrorType'] = $_.Exception.GetType().FullName
    $result['ScriptStackTrace'] = $_.ScriptStackTrace
    Write-BuildLog "Build failed: $message"
    Write-BuildLog $_.ScriptStackTrace
}
finally {
    try { Remove-PrelisSigningFiles $paths }
    catch {
        $result.Status = 'Failed'
        $result.ExitCode = 1
        $result.Error = 'Failed to remove temporary signing files.'
        $exitCode = 1
        Write-BuildLog $result.Error
    }
    if ($writer) { $writer.Dispose() }
    $result.FinishedAt = [DateTime]::UtcNow.ToString('o')
    if (Test-Path -LiteralPath $paths.Directory -PathType Container) {
        Write-PrelisBuildJson $paths.Result $result
    }
    if ($workerLock) { $workerLock.Dispose() }
}
exit $exitCode
