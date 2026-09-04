param(
    [ValidateRange(1, 16)][int]$Workers = 8,
    [ValidateRange(0, 168)][double]$MaxHours = 0,
    [switch]$Foreground
)
$ErrorActionPreference = 'Stop'
$runRoot = $PSScriptRoot
$statePath = Join-Path $runRoot 'process_state.json'
if (Test-Path -LiteralPath $statePath) {
    $prior = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($prior.RProcessId) {
        $existingR = Get-Process -Id ([int]$prior.RProcessId) -ErrorAction SilentlyContinue
        if ($existingR -and $existingR.ProcessName -eq 'Rscript' -and
            $existingR.StartTime.ToUniversalTime().Ticks -eq ([DateTimeOffset]$prior.RStartTimeUtc).UtcDateTime.Ticks) {
            throw 'This R experiment is already active. Refusing a duplicate launch; use status.ps1.'
        }
    }
}
$lockPath = Join-Path $runRoot 'run.lock'
try {
    $probe = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
    $probe.Dispose()
} catch {
    throw 'This run is already active. Use status.ps1; do not launch a second writer.'
}
$hostScript = Join-Path $runRoot 'run_host.ps1'
if ($Foreground) {
    & $hostScript -Workers $Workers -MaxHours $MaxHours
    return
}
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$logs = Join-Path $runRoot 'logs'
[IO.Directory]::CreateDirectory($logs) > $null
$argsList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $hostScript,
    '-Workers', "$Workers", '-MaxHours', $MaxHours.ToString([Globalization.CultureInfo]::InvariantCulture))
$quotedArgs = ($argsList | ForEach-Object { '"' + $_ + '"' }) -join ' '
$hostProcess = Start-Process -FilePath 'powershell.exe' -ArgumentList $quotedArgs `
    -WindowStyle Hidden -WorkingDirectory $runRoot `
    -RedirectStandardOutput (Join-Path $logs "host_$stamp.stdout.log") `
    -RedirectStandardError (Join-Path $logs "host_$stamp.stderr.log") -PassThru
Write-Output "Host started: PID $($hostProcess.Id); requested workers: $Workers."
Write-Output 'Use status.ps1 after startup to confirm the R process and checkpoints.'
