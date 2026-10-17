param(
    [Parameter(Mandatory = $true)]
    [string]$BundleRoot,

    [Parameter(Mandatory = $true)]
    [string]$ApplicationPath,

    [Parameter(Mandatory = $true)]
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$appSignature = Get-AuthenticodeSignature -LiteralPath $ApplicationPath
if ($appSignature.Status -ne 'Valid') {
    throw "Application signature is not valid: $($appSignature.Status)"
}

$files = @(Get-ChildItem -LiteralPath $BundleRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.exe', '.msi') } |
    Sort-Object FullName)
$bundlePathPrefix = [System.IO.Path]::GetFullPath($BundleRoot).TrimEnd('\') + '\'
$results = @(
    foreach ($file in $files) {
        $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
        [pscustomobject]@{
            Path = $file.FullName.Substring($bundlePathPrefix.Length).Replace('\', '/')
            File = $file.Name
            Status = [string]$signature.Status
            Publisher = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { '' }
            Timestamp = [bool]$signature.TimeStamperCertificate
            Sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
)
$results | Format-Table File, Status, Publisher, Timestamp -AutoSize
if (-not ($results | Where-Object { $_.Path -like 'nsis/*-setup.exe' })) {
    throw 'NSIS EXE installer not found.'
}
if (-not ($results | Where-Object { $_.Path -like 'msi/*.msi' })) {
    throw 'MSI installer not found.'
}
if ($results | Where-Object { $_.Status -ne 'Valid' }) {
    throw 'Installer signature verification failed.'
}
$tauriConfigPath = Join-Path (Split-Path -Parent $BundleRoot) '../../tauri.conf.json'
$tauriConfig = Get-Content -LiteralPath $tauriConfigPath -Raw | ConvertFrom-Json
$webviewInstallMode = $tauriConfig.bundle.windows.webviewInstallMode.type
if ([string]::IsNullOrWhiteSpace($webviewInstallMode)) {
    $webviewInstallMode = 'downloadBootstrapper'
}
$report = @{ SchemaVersion = 1; Files = $results; WebviewInstallMode = $webviewInstallMode }
$utf8 = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 5), $utf8)
Write-Host 'EXE and MSI signatures are valid.'
