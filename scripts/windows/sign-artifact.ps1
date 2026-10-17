param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath
)

$ErrorActionPreference = 'Stop'
$signingFailureOutput = ''
$previousDisableIpv6 = [Environment]::GetEnvironmentVariable('DOTNET_SYSTEM_NET_DISABLEIPV6', 'Process')
try {
    foreach ($key in @('PRELIS_SIGNTOOL_PATH', 'PRELIS_ARTIFACT_SIGNING_DLIB_PATH', 'PRELIS_ARTIFACT_SIGNING_METADATA')) {
        if (-not [Environment]::GetEnvironmentVariable($key, 'Process')) {
            throw "Artifact Signing is not configured: $key"
        }
    }

    # The build host can reach Microsoft Entra ID over IPv4, but its IPv6 route times out.
    # Limit the workaround to this SignTool process and its .NET Artifact Signing plugin.
    $env:DOTNET_SYSTEM_NET_DISABLEIPV6 = '1'
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $signingOutput = & $env:PRELIS_SIGNTOOL_PATH sign /v /fd SHA256 `
            /tr 'http://timestamp.acs.microsoft.com' /td SHA256 `
            /dlib $env:PRELIS_ARTIFACT_SIGNING_DLIB_PATH `
            /dmdf $env:PRELIS_ARTIFACT_SIGNING_METADATA $FilePath 2>&1
        $signingExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($signingExitCode -ne 0) {
        $signingFailureOutput = $signingOutput | Out-String
        throw "Artifact Signing failed ($signingExitCode): $FilePath"
    }

    $signingOutput | Write-Output
}
catch {
    if ($env:PRELIS_SIGNING_LOG_PATH) {
        [System.IO.File]::AppendAllText(
            $env:PRELIS_SIGNING_LOG_PATH,
            "Signing failed for ${FilePath}:`r`n$($_ | Out-String)`r`n$signingFailureOutput`r`n"
        )
    }
    throw
}
finally {
    [Environment]::SetEnvironmentVariable('DOTNET_SYSTEM_NET_DISABLEIPV6', $previousDisableIpv6, 'Process')
}
