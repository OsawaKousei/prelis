param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^prelis-signing-[a-zA-Z0-9._-]+\.env$')]
    [string]$CredentialFile
)

$ErrorActionPreference = 'Stop'
$credentialPath = Join-Path $env:USERPROFILE $CredentialFile
$created = $false

try {
    $output = [System.IO.File]::Open($credentialPath, [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $created = $true
    try {
        [Console]::OpenStandardInput().CopyTo($output)
    }
    finally {
        $output.Dispose()
    }
    if ((Get-Item -LiteralPath $credentialPath).Length -eq 0) {
        throw 'No signing credentials were received.'
    }
}
catch {
    if ($created -and (Test-Path -LiteralPath $credentialPath)) {
        Remove-Item -LiteralPath $credentialPath -Force
    }
    throw
}
