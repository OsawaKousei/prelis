param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^prelis-signing-[a-zA-Z0-9._-]+\.env$')]
    [string]$CredentialFile,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^prelis-build-[a-zA-Z0-9._-]+\.ok$')]
    [string]$CompletionFile,

    [switch]$SignOnly
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$credentialPath = Join-Path $env:USERPROFILE $CredentialFile
$completionPath = Join-Path $env:USERPROFILE $CompletionFile
$metadataPath = Join-Path $env:TEMP ("prelis-signing-metadata-{0}.json" -f [guid]::NewGuid().ToString('N'))
$configPath = Join-Path $env:TEMP ("prelis-signing-config-{0}.json" -f [guid]::NewGuid().ToString('N'))
$signOnlyStage = $null
$preserveSignOnlyStage = $false
$utf8 = [System.Text.UTF8Encoding]::new($false)
$signingKeys = @(
    'AZURE_TENANT_ID', 'AZURE_CLIENT_ID', 'AZURE_CLIENT_SECRET',
    'AZURE_ARTIFACT_SIGNING_ENDPOINT', 'AZURE_ARTIFACT_SIGNING_ACCOUNT_NAME',
    'AZURE_ARTIFACT_SIGNING_CERTIFICATE_PROFILE_NAME'
)

try {
    if (-not (Test-Path -LiteralPath $credentialPath -PathType Leaf)) {
        throw "Signing credentials were not found: $credentialPath. Keep the Ubuntu script running and use its latest Windows command."
    }

    $values = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($credentialPath, [System.Text.Encoding]::UTF8)) {
        $separator = $line.IndexOf('=')
        if ($separator -le 0) { throw 'Invalid signing credential file.' }
        $key = $line.Substring(0, $separator)
        if ($key -notin $signingKeys -or $values.ContainsKey($key)) {
            throw 'Invalid or duplicate signing credential key.'
        }
        $values[$key] = $line.Substring($separator + 1)
    }
    foreach ($key in $signingKeys) {
        if (-not $values.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($values[$key])) {
            throw "Signing credential is missing: $key"
        }
    }

    $signTool = $env:PRELIS_SIGNTOOL_PATH
    if (-not $signTool) {
        $sdkBin = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
        if (Test-Path -LiteralPath $sdkBin) {
            $signTool = Get-ChildItem -LiteralPath $sdkBin -Filter signtool.exe -Recurse -File |
                Where-Object { $_.FullName -match '\\x64\\' } |
                Sort-Object FullName -Descending |
                Select-Object -First 1 -ExpandProperty FullName
        }
    }
    if (-not $signTool -or -not (Test-Path -LiteralPath $signTool -PathType Leaf)) {
        throw 'x64 SignTool was not found. Install Artifact Signing Client Tools or set PRELIS_SIGNTOOL_PATH.'
    }

    $dlib = $env:PRELIS_ARTIFACT_SIGNING_DLIB_PATH
    if (-not $dlib) {
        $clientToolDirectories = @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\MicrosoftArtifactSigningClientTools'),
            (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\ArtifactSigningClientTools'),
            (Join-Path $env:ProgramFiles 'Microsoft\ArtifactSigningClientTools')
        )
        foreach ($clientTools in $clientToolDirectories) {
            if (Test-Path -LiteralPath $clientTools -PathType Container) {
                $dlibCandidates = @(Get-ChildItem -LiteralPath $clientTools -Filter Azure.CodeSigning.Dlib.dll -Recurse -File)
                $dlib = $dlibCandidates |
                    Where-Object { $_.FullName -match '\\x64\\' } |
                    Select-Object -First 1 -ExpandProperty FullName
                if (-not $dlib) {
                    $dlib = $dlibCandidates | Select-Object -First 1 -ExpandProperty FullName
                }
                if ($dlib) { break }
            }
        }
    }
    if (-not $dlib -or -not (Test-Path -LiteralPath $dlib -PathType Leaf)) {
        throw 'Artifact Signing x64 dlib was not found. Install Client Tools or set PRELIS_ARTIFACT_SIGNING_DLIB_PATH.'
    }

    $metadata = @{
        Endpoint = $values['AZURE_ARTIFACT_SIGNING_ENDPOINT']
        CodeSigningAccountName = $values['AZURE_ARTIFACT_SIGNING_ACCOUNT_NAME']
        CertificateProfileName = $values['AZURE_ARTIFACT_SIGNING_CERTIFICATE_PROFILE_NAME']
    }
    [System.IO.File]::WriteAllText($metadataPath, ($metadata | ConvertTo-Json -Compress), $utf8)
    $env:PRELIS_SIGNTOOL_PATH = $signTool
    $env:PRELIS_ARTIFACT_SIGNING_DLIB_PATH = $dlib
    $env:PRELIS_ARTIFACT_SIGNING_METADATA = $metadataPath

    $signScript = Join-Path $PSScriptRoot 'sign-artifact.ps1'
    $bundleRoot = Join-Path $repoRoot 'apps/desktop/src-tauri/target/release/bundle'
    $appExe = Join-Path $repoRoot 'apps/desktop/src-tauri/target/release/desktop.exe'

    if ($SignOnly) {
        $nsisDir = Join-Path $bundleRoot 'nsis'
        $msiDir = Join-Path $bundleRoot 'msi'
        if (-not (Test-Path -LiteralPath $nsisDir -PathType Container) -or
            -not (Test-Path -LiteralPath $msiDir -PathType Container)) {
            throw 'Existing NSIS and MSI installer directories are required for sign-only mode.'
        }
        $nsis = @(Get-ChildItem -LiteralPath $nsisDir -Filter '*-setup.exe' -File)
        $msi = @(Get-ChildItem -LiteralPath $msiDir -Filter '*.msi' -File)
        if ($nsis.Count -eq 0 -or $msi.Count -eq 0) {
            throw 'Existing NSIS and MSI installers are required for sign-only mode.'
        }

        $files = @()
        foreach ($file in ($nsis + $msi)) { $files += $file.FullName }
        if (Test-Path -LiteralPath $appExe -PathType Leaf) { $files += $appExe }
        $signOnlyStage = Join-Path $env:TEMP ("prelis-sign-only-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $signOnlyStage | Out-Null

        foreach ($key in @('AZURE_TENANT_ID', 'AZURE_CLIENT_ID', 'AZURE_CLIENT_SECRET')) {
            [Environment]::SetEnvironmentVariable($key, $values[$key], 'Process')
        }
        $stagedFiles = @()
        $index = 0
        foreach ($file in $files) {
            $extension = [System.IO.Path]::GetExtension($file)
            $signedPath = Join-Path $signOnlyStage ("signed-{0}{1}" -f $index, $extension)
            $backupPath = Join-Path $signOnlyStage ("backup-{0}{1}" -f $index, $extension)
            Copy-Item -LiteralPath $file -Destination $signedPath
            Copy-Item -LiteralPath $file -Destination $backupPath
            & $signScript -FilePath $signedPath
            & $signTool verify /pa /all $signedPath
            if ($LASTEXITCODE -ne 0) { throw "Signature verification failed: $file" }
            $stagedFiles += [pscustomobject]@{ Original = $file; Signed = $signedPath; Backup = $backupPath }
            $index++
        }

        try {
            foreach ($entry in $stagedFiles) {
                Copy-Item -LiteralPath $entry.Signed -Destination $entry.Original -Force
                & $signTool verify /pa /all $entry.Original
                if ($LASTEXITCODE -ne 0) { throw "Signature verification failed: $($entry.Original)" }
            }
        }
        catch {
            $restoreFailed = $false
            foreach ($entry in $stagedFiles) {
                try {
                    Copy-Item -LiteralPath $entry.Backup -Destination $entry.Original -Force
                }
                catch {
                    Write-Warning "Could not restore $($entry.Original): $_"
                    $restoreFailed = $true
                }
            }
            if ($restoreFailed) {
                $preserveSignOnlyStage = $true
                Write-Warning "Original copies are preserved at $signOnlyStage"
            }
            throw
        }
        [System.IO.File]::WriteAllText($completionPath, 'signed', $utf8)
        Write-Host 'Existing Windows artifacts signed and verified. No build was run.'
        return
    }

    $config = @{
        bundle = @{
            windows = @{
                signCommand = @{
                    cmd = 'powershell.exe'
                    args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $signScript, '%1')
                }
            }
        }
    }
    [System.IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 6 -Compress), $utf8)

    Set-Location $repoRoot
    foreach ($bundleType in @('nsis', 'msi')) {
        $oldBundle = Join-Path $bundleRoot $bundleType
        if (Test-Path -LiteralPath $oldBundle) { Remove-Item -LiteralPath $oldBundle -Recurse -Force }
    }
    if (Test-Path -LiteralPath $completionPath) { Remove-Item -LiteralPath $completionPath -Force }

    & npm.cmd ci --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw "npm ci failed ($LASTEXITCODE)." }

    foreach ($key in @('AZURE_TENANT_ID', 'AZURE_CLIENT_ID', 'AZURE_CLIENT_SECRET')) {
        [Environment]::SetEnvironmentVariable($key, $values[$key], 'Process')
    }
    & npm.cmd run build:desktop -- --bundles nsis,msi --config $configPath
    if ($LASTEXITCODE -ne 0) { throw "Tauri build failed ($LASTEXITCODE)." }

    $nsis = @(Get-ChildItem -Path (Join-Path $bundleRoot 'nsis') -Filter '*-setup.exe' -File)
    $msi = @(Get-ChildItem -Path (Join-Path $bundleRoot 'msi') -Filter '*.msi' -File)
    if (-not (Test-Path -LiteralPath $appExe -PathType Leaf) -or $nsis.Count -eq 0 -or $msi.Count -eq 0) {
        throw 'The application executable, NSIS installer, or MSI installer is missing.'
    }
    foreach ($file in @($appExe) + @($nsis.FullName) + @($msi.FullName)) {
        & $signTool verify /pa /all $file
        if ($LASTEXITCODE -ne 0) { throw "Signature verification failed: $file" }
    }
    [System.IO.File]::WriteAllText($completionPath, 'signed', $utf8)
    Write-Host 'Signed Windows build completed.'
}
finally {
    if ($signOnlyStage -and -not $preserveSignOnlyStage -and (Test-Path -LiteralPath $signOnlyStage)) {
        Remove-Item -LiteralPath $signOnlyStage -Recurse -Force
    }
    foreach ($path in @($credentialPath, $metadataPath, $configPath)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    foreach ($key in @('AZURE_TENANT_ID', 'AZURE_CLIENT_ID', 'AZURE_CLIENT_SECRET',
                      'PRELIS_SIGNTOOL_PATH', 'PRELIS_ARTIFACT_SIGNING_DLIB_PATH',
                      'PRELIS_ARTIFACT_SIGNING_METADATA')) {
        [Environment]::SetEnvironmentVariable($key, $null, 'Process')
    }
}
