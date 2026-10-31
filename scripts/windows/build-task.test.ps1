# Offline tests only: no SSH connection, COM task registration or build is performed.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'build-task-common.ps1')
$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('prelis-build-task-test-' + [guid]::NewGuid().ToString('N'))
$previousProfile = $env:USERPROFILE

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

try {
    $syntaxTrees = @{}
    foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1') {
        $tokens = $null
        $parseErrors = $null
        $tree = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        Assert-Condition ($parseErrors.Count -eq 0) ("Syntax errors in " + $file.Name + ': ' + ($parseErrors.Message -join '; '))
        $syntaxTrees[$file.Name] = $tree
    }
    New-Item -ItemType Directory -Path $testDirectory | Out-Null
    $fixtureRepo = Join-Path $testDirectory 'version-repo'
    $fixtureDesktop = Join-Path $fixtureRepo 'apps/desktop'
    New-Item -ItemType Directory -Path (Join-Path $fixtureDesktop 'src-tauri') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $fixtureDesktop 'package.json'), '{"version":"0.1.3"}')
    [IO.File]::WriteAllText((Join-Path $fixtureDesktop 'src-tauri/tauri.conf.json'), '{"version":"0.1.3"}')
    [IO.File]::WriteAllText((Join-Path $fixtureDesktop 'src-tauri/Cargo.toml'), "[package]`nversion = `"0.1.3`"`n[dependencies]`n")
    Assert-Condition ((Get-PrelisDesktopVersion $fixtureRepo) -eq '0.1.3') 'Windows source version check failed.'
    [IO.File]::WriteAllText((Join-Path $fixtureDesktop 'package.json'), '{"version":"0.1.2"}')
    $rejected = $false
    try { $null = Get-PrelisDesktopVersion $fixtureRepo } catch { $rejected = $true }
    Assert-Condition $rejected 'Windows source version drift must be rejected.'
    $nativeProbe = Join-Path $testDirectory 'native-progress.ps1'
    $shellExecutable = (Get-Process -Id $PID).Path
    [IO.File]::WriteAllText($nativeProbe, '[Console]::Error.WriteLine("native progress"); exit 0')
    $nativeOutput = @(Invoke-PrelisBuildCommand -FilePath $shellExecutable `
        -Arguments @('-NoProfile', '-NonInteractive', '-File', $nativeProbe) -Description 'progress probe' *>&1)
    Assert-Condition (($nativeOutput | Out-String).Contains('native progress')) 'Native stderr progress was lost.'
    [IO.File]::WriteAllText($nativeProbe, 'exit 7')
    $rejected = $false
    try {
        Invoke-PrelisBuildCommand -FilePath $shellExecutable `
            -Arguments @('-NoProfile', '-NonInteractive', '-File', $nativeProbe) -Description 'failure probe' *> $null
    } catch { $rejected = $true }
    Assert-Condition $rejected 'A nonzero native exit code must fail the build.'
    $rejected = $false
    try { Invoke-PrelisBuildCommand -FilePath (Join-Path $testDirectory 'missing.exe') -Description 'missing command' }
    catch { $rejected = $true }
    Assert-Condition $rejected 'A missing native command must fail the build.'
    $env:USERPROFILE = $testDirectory
    $BuildId = '0123456789abcdef0123456789abcdef'
    $paths = Get-PrelisBuildPaths $BuildId
    Assert-Condition ($paths.CredentialFile -eq "prelis-signing-$BuildId.env") 'Wrong credential path.'
    $rejected = $false
    try { $null = Get-PrelisBuildPaths '../another-job' } catch { $rejected = $true }
    Assert-Condition $rejected 'Invalid build IDs must be rejected.'

    New-Item -ItemType Directory -Path $paths.SigningDirectory -Force | Out-Null
    [IO.File]::WriteAllText($paths.Credential, 'test credential')
    [IO.File]::WriteAllText($paths.Completion, 'signed')
    [IO.File]::WriteAllText((Join-Path $paths.SigningDirectory 'metadata.json'), '{}')
    [IO.File]::WriteAllText($paths.Log, 'keep this log')
    Write-PrelisBuildJson $paths.Result @{ BuildId = $BuildId; Status = 'Succeeded'; ExitCode = 0 }
    $json = Read-PrelisBuildJson $paths.Result
    Assert-Condition ($json.BuildId -eq $BuildId -and $json.ExitCode -eq 0) 'Result JSON round trip failed.'
    $localizedError = "Error: $([char]0x65e5)$([char]0x672c)$([char]0x8a9e)"
    Write-PrelisBuildJson $paths.Result @{ BuildId = $BuildId; Status = 'Failed'; ExitCode = 1; Error = $localizedError }
    Assert-Condition ((Read-PrelisBuildJson $paths.Result).Error -eq $localizedError) 'BOM-less UTF-8 errors were corrupted.'
    Write-PrelisBuildJson $paths.Result @{ BuildId = $BuildId; Status = 'Succeeded'; ExitCode = 0 }
    Remove-PrelisSigningFiles $paths
    Assert-Condition (-not (Test-Path -LiteralPath $paths.Credential)) 'Credentials were not deleted.'
    Assert-Condition (-not (Test-Path -LiteralPath $paths.SigningDirectory)) 'Signing metadata was not deleted.'
    Assert-Condition ((Get-Content -LiteralPath $paths.Log -Raw) -eq 'keep this log') 'Logs must be preserved.'

    # Load only the cancellation function's AST, without executing the controller.
    $ast = $syntaxTrees['invoke-build-task.ps1']
    $stopFunction = $ast.Find({ param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Stop-BuildTask'
    }, $true)
    Set-Item Function:Stop-BuildTask -Value $stopFunction.Body.GetScriptBlock()
    $identity = [pscustomobject]@{ User = [pscustomobject]@{ Value = 'S-1-5-21-123-456-789-1001' } }
    $runnerPath = Join-Path $testDirectory 'run-build-task.ps1'
    $powerShellPath = Join-Path $testDirectory 'powershell.exe'
    $action = [pscustomobject]@{
        Path = $powerShellPath
        Arguments = '-NoProfile -File "' + $runnerPath + '" -BuildId ' + $BuildId + ' -ExpectedUserSid S-1-5-21-123-456-789-1001'
    }
    $actions = [pscustomobject]@{ Count = 1 }
    $actions | Add-Member ScriptMethod Item { param($index) return $action }
    $registered = [pscustomobject]@{
        Definition = [pscustomobject]@{
            Principal = [pscustomobject]@{ UserId = $identity.User.Value }
            Actions = $actions
        }
    }
    $registered | Add-Member ScriptMethod GetInstances { param($flags) return [pscustomobject]@{ Count = 0 } }
    $folder = [pscustomobject]@{ Deleted = $null }
    $folder | Add-Member ScriptMethod DeleteTask { param($name, $flags) $this.Deleted = $name }
    function Get-BuildTask { return $registered }

    Stop-BuildTask
    Assert-Condition ($folder.Deleted -eq $paths.TaskName) 'The matching completed task was not deleted.'
    Assert-Condition ((Read-PrelisBuildJson $paths.Result).Status -eq 'Succeeded') 'Cleanup replaced a successful result.'

    $folder.Deleted = $null
    [IO.File]::WriteAllText($paths.Credential, 'preserve on identity mismatch')
    $registered.Definition.Principal.UserId = 'S-1-5-21-123-456-789-1002'
    $rejected = $false
    try { Stop-BuildTask } catch { $rejected = $true }
    Assert-Condition $rejected 'A different user task must not be stopped.'
    Assert-Condition ($null -eq $folder.Deleted) 'A different user task was deleted.'
    Assert-Condition (Test-Path -LiteralPath $paths.Credential) 'Credentials were deleted before task ownership was established.'

    $registered.Definition.Principal.UserId = $identity.User.Value
    $action.Arguments = '-File "other-script.ps1"'
    $rejected = $false
    try { Stop-BuildTask } catch { $rejected = $true }
    Assert-Condition $rejected 'A different task action must not be stopped.'
    Assert-Condition ($null -eq $folder.Deleted) 'A different action task was deleted.'

    $action.Arguments = '-NoProfile -File "' + $runnerPath + '" -BuildId ' + $BuildId + ' -ExpectedUserSid S-1-5-21-123-456-789-1001'
    Write-PrelisBuildJson $paths.Worker @{
        BuildId = $BuildId; UserSid = $identity.User.Value; SessionId = 1
        ProcessId = $PID; StartTimeTicks = '0'
    }
    Stop-BuildTask
    Assert-Condition ($folder.Deleted -eq $paths.TaskName) 'Cleanup failed after the original worker exited.'
    Assert-Condition ($null -ne (Get-Process -Id $PID)) 'A reused PID was terminated.'

    $logFunction = $syntaxTrees['run-build-task.ps1'].Find({ param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Write-BuildLog'
    }, $true)
    Set-Item Function:Write-BuildLog -Value $logFunction.Body.GetScriptBlock()
    $secret = 'fake-client-secret'
    $writer = [IO.StreamWriter]::new($paths.Log, $false, [Text.UTF8Encoding]::new($false))
    try { Write-BuildLog ('example: ' + $secret) } finally { $writer.Dispose(); $writer = $null }
    $logText = Get-Content -LiteralPath $paths.Log -Raw
    Assert-Condition ($logText.Contains('[redacted]') -and -not $logText.Contains($secret)) 'Client secret was not redacted.'

    # Exercise the actual runner's output pipeline with Format-Table records.
    $buildPipeline = $syntaxTrees['run-build-task.ps1'].Find({ param($node)
        $node -is [System.Management.Automation.Language.PipelineAst] -and
        $node.PipelineElements[0].Extent.Text.Contains("'build.ps1'")
    }, $true)
    $tail = @($buildPipeline.PipelineElements | Select-Object -Skip 1 | ForEach-Object { $_.Extent.Text }) -join ' | '
    $fixturePipeline = '& { [pscustomobject]@{File="fixture.exe";Status="Valid"} | Format-Table File,Status } | ' + $tail
    $writer = [IO.StreamWriter]::new($paths.Log, $false, [Text.UTF8Encoding]::new($false))
    try { & ([scriptblock]::Create($fixturePipeline)) } finally { $writer.Dispose(); $writer = $null }
    Assert-Condition (([IO.File]::ReadAllText($paths.Log)).Contains('fixture.exe')) 'Formatted child output was not logged.'
    Write-Output 'PASS: PowerShell syntax, native exit codes, UTF-8 JSON, formatted logs, cleanup, task/action/PID guards and secret redaction.'
}
finally {
    $env:USERPROFILE = $previousProfile
    if (Test-Path -LiteralPath $testDirectory) { Remove-Item -LiteralPath $testDirectory -Recurse -Force }
}
