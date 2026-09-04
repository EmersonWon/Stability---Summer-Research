$ErrorActionPreference = 'Stop'
$resultsDir = Join-Path $PSScriptRoot 'results'
if (-not (Test-Path -LiteralPath $resultsDir)) { throw 'This run has not started.' }
$controlDir = Join-Path $resultsDir 'control'
[IO.Directory]::CreateDirectory($controlDir) > $null
$target = Join-Path $controlDir 'pause.request.json'
$temporary = Join-Path $controlDir ('pause_' + [Guid]::NewGuid().ToString('N') + '.tmp')
$request = @{ requested_at_utc = (Get-Date).ToUniversalTime().ToString('o'); reason = 'user_safe_pause' }
[IO.File]::WriteAllText($temporary, ($request | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
if (Test-Path -LiteralPath $target) { [IO.File]::Replace($temporary, $target, (Join-Path $controlDir 'pause.previous.json')) }
else { [IO.File]::Move($temporary, $target) }
Write-Output 'Pause requested. Workers finish their current fit, save it, then stop. Wait for status=paused before closing.'
