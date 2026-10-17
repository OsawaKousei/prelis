$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Set-Location $repoRoot

& npm.cmd ci --no-audit --no-fund
if ($LASTEXITCODE -ne 0) { throw "npm ci failed ($LASTEXITCODE)." }

& npm.cmd run build:desktop -- --bundles nsis,msi
if ($LASTEXITCODE -ne 0) { throw "Tauri build failed ($LASTEXITCODE)." }
