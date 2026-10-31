param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^prelis-signing-[a-zA-Z0-9._-]+\.env$')]
    [string]$CredentialFile,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^prelis-build-[a-zA-Z0-9._-]+\.ok$')]
    [string]$CompletionFile,

    [ValidatePattern('^[a-f0-9]{32}$')]
    [string]$BuildId
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'build-task-common.ps1')
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$credentialPath = Join-Path $env:USERPROFILE $CredentialFile
$completionPath = Join-Path $env:USERPROFILE $CompletionFile
$metadataPath = Join-Path $env:TEMP ("prelis-signing-metadata-{0}.json" -f [guid]::NewGuid().ToString('N'))
$configPath = Join-Path $env:TEMP ("prelis-signing-config-{0}.json" -f [guid]::NewGuid().ToString('N'))
$signingLogPath = Join-Path $env:TEMP ("prelis-signing-output-{0}.log" -f [guid]::NewGuid().ToString('N'))
$bundleRoot = Join-Path $repoRoot 'apps/desktop/src-tauri/target/release/bundle'
$reportPath = Join-Path $bundleRoot 'prelis-signature-report.json'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$signingKeys = @(
    'AZURE_TENANT_ID', 'AZURE_CLIENT_ID', 'AZURE_CLIENT_SECRET',
    'AZURE_ARTIFACT_SIGNING_ENDPOINT', 'AZURE_ARTIFACT_SIGNING_ACCOUNT_NAME',
    'AZURE_ARTIFACT_SIGNING_CERTIFICATE_PROFILE_NAME'
)
$values = @{}

try {
    $version = Get-PrelisDesktopVersion $repoRoot
    Write-Output "Desktop release version: $version"
    if ($BuildId) {
        $jobPaths = Get-PrelisBuildPaths $BuildId
        if ($CredentialFile -ne $jobPaths.CredentialFile -or $CompletionFile -ne $jobPaths.CompletionFile) {
            throw 'The credential and completion files do not match this build job.'
        }
        New-Item -ItemType Directory -Path $jobPaths.SigningDirectory -Force | Out-Null
        $metadataPath = Join-Path $jobPaths.SigningDirectory 'metadata.json'
        $configPath = Join-Path $jobPaths.SigningDirectory 'config.json'
        $signingLogPath = Join-Path $jobPaths.SigningDirectory 'signing.log'
    }
    if (-not (Test-Path -LiteralPath $credentialPath -PathType Leaf)) {
        throw "Signing credentials were not found: $credentialPath. Start a new build from Ubuntu."
    }

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
        # Use the supplied service-principal credentials without interactive or cached fallbacks.
        ExcludeCredentials = @(
            'ManagedIdentityCredential', 'WorkloadIdentityCredential', 'SharedTokenCacheCredential',
            'VisualStudioCredential', 'VisualStudioCodeCredential', 'AzureCliCredential',
            'AzurePowerShellCredential', 'AzureDeveloperCliCredential', 'InteractiveBrowserCredential'
        )
    }
    [System.IO.File]::WriteAllText($metadataPath, ($metadata | ConvertTo-Json -Compress), $utf8)
    $env:PRELIS_SIGNTOOL_PATH = $signTool
    $env:PRELIS_ARTIFACT_SIGNING_DLIB_PATH = $dlib
    $env:PRELIS_ARTIFACT_SIGNING_METADATA = $metadataPath
    $env:PRELIS_SIGNING_LOG_PATH = $signingLogPath

    $signScript = Join-Path $PSScriptRoot 'sign-artifact.ps1'
    $appExe = Join-Path $repoRoot 'apps/desktop/src-tauri/target/release/desktop.exe'

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
    if (Test-Path -LiteralPath $reportPath) { Remove-Item -LiteralPath $reportPath -Force }
    foreach ($bundleType in @('nsis', 'msi')) {
        $oldBundle = Join-Path $bundleRoot $bundleType
        if (Test-Path -LiteralPath $oldBundle) { Remove-Item -LiteralPath $oldBundle -Recurse -Force }
    }
    if (Test-Path -LiteralPath $completionPath) { Remove-Item -LiteralPath $completionPath -Force }

    Write-Output 'Installing npm dependencies.'
    Invoke-PrelisBuildCommand -FilePath 'npm.cmd' -Arguments @('ci', '--no-audit', '--no-fund') -Description 'npm ci'

    foreach ($key in @('AZURE_TENANT_ID', 'AZURE_CLIENT_ID', 'AZURE_CLIENT_SECRET')) {
        [Environment]::SetEnvironmentVariable($key, $values[$key], 'Process')
    }
    Write-Output 'Building and signing NSIS and MSI installers.'
    Invoke-PrelisBuildCommand -FilePath 'npm.cmd' `
        -Arguments @('run', 'build:desktop', '--', '--bundles', 'nsis,msi', '--config', $configPath) -Description 'Tauri build'

    $nsis = @(Get-ChildItem -LiteralPath (Join-Path $bundleRoot 'nsis') -Filter '*-setup.exe' -File)
    $msi = @(Get-ChildItem -LiteralPath (Join-Path $bundleRoot 'msi') -Filter '*.msi' -File)
    if (-not (Test-Path -LiteralPath $appExe -PathType Leaf) -or $nsis.Count -eq 0 -or $msi.Count -eq 0) {
        throw 'The application executable, NSIS installer, or MSI installer is missing.'
    }
    # Tauri restores the unsigned main executable after building each installer.
    # The copies embedded in NSIS and MSI were signed during bundling; sign the
    # standalone executable again before the final verification.
    & $signScript -FilePath $appExe
    foreach ($file in @($appExe) + @($nsis.FullName) + @($msi.FullName)) {
        Invoke-PrelisBuildCommand -FilePath $signTool -Arguments @('verify', '/pa', '/all', $file) -Description "Signature verification: $file"
    }
    & (Join-Path $PSScriptRoot 'verify-signatures.ps1') `
        -BundleRoot $bundleRoot -ApplicationPath $appExe -ReportPath $reportPath
    [System.IO.File]::WriteAllText($completionPath, 'signed', $utf8)
    Write-Output 'Signed Windows build completed.'
}
catch {
    if (Test-Path -LiteralPath $signingLogPath -PathType Leaf) {
        $diagnosticLines = @(Get-Content -LiteralPath $signingLogPath -Encoding UTF8)
        if ($diagnosticLines.Count -gt 120) {
            $diagnosticLines = @($diagnosticLines[0..39]) + @('... middle of signing output omitted ...') +
                @($diagnosticLines[($diagnosticLines.Count - 80)..($diagnosticLines.Count - 1)])
        }
        $diagnostics = $diagnosticLines -join [Environment]::NewLine
        if ($values -and $values.ContainsKey('AZURE_CLIENT_SECRET') -and $values['AZURE_CLIENT_SECRET']) {
            $diagnostics = $diagnostics.Replace($values['AZURE_CLIENT_SECRET'], '[redacted]')
        }
        Write-Output "Artifact Signing diagnostics:`n$diagnostics"
    }
    throw
}
finally {
    foreach ($path in @($credentialPath, $metadataPath, $configPath, $signingLogPath)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    foreach ($key in @('AZURE_TENANT_ID', 'AZURE_CLIENT_ID', 'AZURE_CLIENT_SECRET',
                      'PRELIS_SIGNTOOL_PATH', 'PRELIS_ARTIFACT_SIGNING_DLIB_PATH',
                      'PRELIS_ARTIFACT_SIGNING_METADATA', 'PRELIS_SIGNING_LOG_PATH')) {
        [Environment]::SetEnvironmentVariable($key, $null, 'Process')
    }
}
