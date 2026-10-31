# Shared paths, result writes and checked native commands for scheduled builds.
function Invoke-PrelisBuildCommand {
    param([string]$FilePath, [string[]]$Arguments, [string]$Description)

    # Windows PowerShell 5.1 can turn redirected native stderr into ErrorRecords.
    # Build tools write progress to stderr too; use their exit code for failure.
    $command = Get-Command -Name $FilePath -CommandType Application -ErrorAction Stop
    $commandExitCode = $null
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $command.Source @Arguments 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message }
            else { $_ }
        }
        $commandExitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    if ($null -eq $commandExitCode -or $commandExitCode -ne 0) { throw "$Description failed ($commandExitCode)." }
}

function Get-PrelisBuildPaths {
    param([Parameter(Mandatory = $true)][ValidatePattern('^[a-f0-9]{32}$')][string]$BuildId)

    $directory = Join-Path (Join-Path $env:USERPROFILE 'prelis-build-jobs') $BuildId
    [pscustomobject]@{
        BuildId = $BuildId
        Directory = $directory
        Log = Join-Path $directory 'build.log'
        Result = Join-Path $directory 'result.json'
        Worker = Join-Path $directory 'worker.json'
        SigningDirectory = Join-Path $directory 'signing'
        CredentialFile = "prelis-signing-$BuildId.env"
        Credential = Join-Path $env:USERPROFILE "prelis-signing-$BuildId.env"
        CompletionFile = "prelis-build-$BuildId.ok"
        Completion = Join-Path $env:USERPROFILE "prelis-build-$BuildId.ok"
        TaskName = "prelis-build-$BuildId"
    }
}

function Write-PrelisBuildJson {
    param([string]$Path, [object]$Value)

    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Read-PrelisBuildJson {
    param([string]$Path)
    # Windows PowerShell 5.1 otherwise reads BOM-less UTF-8 as the ANSI code page.
    [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json
}

function Get-PrelisDesktopVersion {
    param([string]$RepoRoot)
    $desktop = Join-Path $RepoRoot 'apps/desktop'
    $package = Read-PrelisBuildJson (Join-Path $desktop 'package.json')
    $config = Read-PrelisBuildJson (Join-Path $desktop 'src-tauri/tauri.conf.json')
    $cargo = [IO.File]::ReadAllText((Join-Path $desktop 'src-tauri/Cargo.toml'), [Text.Encoding]::UTF8)
    $section = [regex]::Match($cargo, '(?ms)^\[package\]\s*(.*?)(?=^\[|\z)')
    $cargoVersion = [regex]::Match($section.Groups[1].Value, '(?m)^version\s*=\s*"([^"]+)"').Groups[1].Value
    if ($config.version -notmatch '^\d+\.\d+\.\d+$' -or $package.version -ne $config.version -or $cargoVersion -ne $config.version) {
        throw 'Desktop package.json, tauri.conf.json and Cargo.toml versions do not match.'
    }
    return [string]$config.version
}

function Get-PrelisMsiVersion {
    param([string]$Path)
    $installer = $database = $view = $record = $null
    try {
        $installer = New-Object -ComObject 'WindowsInstaller.Installer'
        $database = $installer.OpenDatabase($Path, 0) # Read-only; does not install the package.
        $view = $database.OpenView('SELECT `Value` FROM `Property` WHERE `Property` = ''ProductVersion''')
        [void]$view.Execute()
        $record = $view.Fetch()
        if (-not $record) { throw 'The MSI has no ProductVersion property.' }
        return [string]$record.StringData(1)
    }
    finally {
        if ($view) { [void]$view.Close() }
        foreach ($item in @($record, $view, $database, $installer)) {
            if ($item) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($item) }
        }
    }
}

function Get-PrelisExeVersion {
    param([string]$Path, [string]$ExpectedVersion)
    $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
    $version = '{0}.{1}.{2}' -f $info.FileMajorPart, $info.FileMinorPart, $info.FileBuildPart
    if ($version -ne $ExpectedVersion -or $info.FilePrivatePart -ne 0) {
        throw "Executable file version does not match ${ExpectedVersion}: $Path ($($info.FileVersion))"
    }
    return $version
}

function Remove-PrelisSigningFiles {
    param([object]$Paths)

    foreach ($path in @($Paths.Credential, $Paths.Completion)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    if (Test-Path -LiteralPath $Paths.SigningDirectory) {
        Remove-Item -LiteralPath $Paths.SigningDirectory -Recurse -Force
    }
}
