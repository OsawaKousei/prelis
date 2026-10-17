param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath
)

$ErrorActionPreference = 'Stop'
foreach ($key in @('PRELIS_SIGNTOOL_PATH', 'PRELIS_ARTIFACT_SIGNING_DLIB_PATH', 'PRELIS_ARTIFACT_SIGNING_METADATA')) {
    if (-not [Environment]::GetEnvironmentVariable($key, 'Process')) {
        throw "Artifact Signing is not configured: $key"
    }
}

& $env:PRELIS_SIGNTOOL_PATH sign /v /fd SHA256 /tr 'http://timestamp.acs.microsoft.com' /td SHA256 `
    /dlib $env:PRELIS_ARTIFACT_SIGNING_DLIB_PATH /dmdf $env:PRELIS_ARTIFACT_SIGNING_METADATA $FilePath
if ($LASTEXITCODE -ne 0) { throw "Artifact Signing failed ($LASTEXITCODE): $FilePath" }
