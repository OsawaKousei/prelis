param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^prelis-signing-[a-zA-Z0-9._-]+\.env$')]
    [string]$CredentialFile,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^prelis-build-[a-zA-Z0-9._-]+\.ok$')]
    [string]$CompletionFile
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$credentialPath = Join-Path $env:USERPROFILE $CredentialFile
$completionPath = Join-Path $env:USERPROFILE $CompletionFile
$metadataPath = Join-Path $env:TEMP ("prelis-signing-metadata-{0}.json" -f [guid]::NewGuid().ToString('N'))
$configPath = Join-Path $env:TEMP ("prelis-signing-config-{0}.json" -f [guid]::NewGuid().ToString('N'))
$utf8 = [System.Text.UTF8Encoding]::new($false)
$signingKeys = @(
    'AZURE_TENANT_ID', 'AZURE_CLIENT_ID', 'AZURE_CLIENT_SECRET',
    'AZURE_ARTIFACT_SIGNING_ENDPOINT', 'AZURE_ARTIFACT_SIGNING_ACCOUNT_NAME',
    'AZURE_ARTIFACT_SIGNING_CERTIFICATE_PROFILE_NAME'
)

try {
    if (-not (Test-Path -LiteralPath $credentialPath -PathType Leaf)) {
        throw "Signing credentials were not found: $credentialPath"
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
        $clientTools = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\ArtifactSigningClientTools'
        if (Test-Path -LiteralPath $clientTools) {
            $dlibCandidates = @(Get-ChildItem -LiteralPath $clientTools -Filter Azure.CodeSigning.Dlib.dll -Recurse -File)
            $dlib = $dlibCandidates |
                Where-Object { $_.FullName -match '\\x64\\' } |
                Select-Object -First 1 -ExpandProperty FullName
            if (-not $dlib) {
                $dlib = $dlibCandidates | Select-Object -First 1 -ExpandProperty FullName
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
    $bundleRoot = Join-Path $repoRoot 'apps/desktop/src-tauri/target/release/bundle'
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

    $appExe = Join-Path $repoRoot 'apps/desktop/src-tauri/target/release/desktop.exe'
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
    foreach ($path in @($credentialPath, $metadataPath, $configPath)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    foreach ($key in @('AZURE_TENANT_ID', 'AZURE_CLIENT_ID', 'AZURE_CLIENT_SECRET',
                      'PRELIS_SIGNTOOL_PATH', 'PRELIS_ARTIFACT_SIGNING_DLIB_PATH',
                      'PRELIS_ARTIFACT_SIGNING_METADATA')) {
        [Environment]::SetEnvironmentVariable($key, $null, 'Process')
    }
}
