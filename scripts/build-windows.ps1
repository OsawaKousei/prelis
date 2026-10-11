$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $repoRoot

if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) {
    throw 'Node.js was not found.'
}
if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
    throw 'npm.cmd was not found.'
}
if (-not (Get-Command cargo.exe -ErrorAction SilentlyContinue)) {
    throw 'Rust/Cargo was not found.'
}

& npm.cmd ci --no-audit --no-fund
if ($LASTEXITCODE -ne 0) { throw "npm ci failed ($LASTEXITCODE)." }

& npm.cmd run build:desktop -- --bundles nsis
if ($LASTEXITCODE -ne 0) { throw "Tauri build failed ($LASTEXITCODE)." }

$releaseDir = Join-Path $repoRoot 'apps/desktop/src-tauri/target/release'
$exe = Join-Path $releaseDir 'desktop.exe'
$nsisDir = Join-Path $releaseDir 'bundle/nsis'
$tauriConfig = Get-Content -LiteralPath (Join-Path $repoRoot 'apps/desktop/src-tauri/tauri.conf.json') -Raw | ConvertFrom-Json
$installerPattern = '{0}_{1}_*-setup.exe' -f $tauriConfig.productName, $tauriConfig.version
$installers = @(Get-ChildItem -LiteralPath $nsisDir -Filter $installerPattern -File)
if (-not (Test-Path -LiteralPath $exe) -or $installers.Count -eq 0) {
    throw 'Windows executable or NSIS installer was not found.'
}

$artifactDir = Join-Path $repoRoot 'windows-artifacts'
New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null
Get-ChildItem -LiteralPath $artifactDir -File | Remove-Item -Force
Copy-Item -LiteralPath $exe -Destination $artifactDir
foreach ($installer in $installers) {
    Copy-Item -LiteralPath $installer.FullName -Destination $artifactDir
}
Get-ChildItem -LiteralPath $artifactDir -File | Get-FileHash -Algorithm SHA256 |
    ForEach-Object { '{0}  {1}' -f $_.Hash.ToLowerInvariant(), (Split-Path $_.Path -Leaf) } |
    Set-Content -LiteralPath (Join-Path $artifactDir 'SHA256SUMS') -Encoding ASCII
Get-ChildItem -LiteralPath $artifactDir -File | Select-Object Name, Length | Format-Table -AutoSize
