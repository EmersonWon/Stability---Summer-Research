$ErrorActionPreference = 'Stop'
$runRoot = $PSScriptRoot
$profile = Get-Content -LiteralPath (Join-Path $runRoot 'run_profile.json') -Raw | ConvertFrom-Json
$resultsDir = Join-Path $runRoot 'results'
$statePath = Join-Path $runRoot 'process_state.json'
$state = if (Test-Path -LiteralPath $statePath) {
    Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
} else { $null }

$rProcess = if ($state -and $state.RProcessId) {
    Get-Process -Id ([int]$state.RProcessId) -ErrorAction SilentlyContinue
} else { $null }
$rActive = [bool](
    $rProcess -and $rProcess.ProcessName -eq 'Rscript' -and
    $rProcess.StartTime.ToUniversalTime().Ticks -eq
        ([DateTimeOffset]$state.RStartTimeUtc).UtcDateTime.Ticks
)
$hostActive = if ($state -and $state.HostProcessId) {
    [bool](Get-Process -Id ([int]$state.HostProcessId) -ErrorAction SilentlyContinue)
} else { $false }

$files = @(Get-ChildItem -LiteralPath (Join-Path $resultsDir 'checkpoints') `
    -Filter '*.rds' -Recurse -File -ErrorAction SilentlyContinue)
$deletions = @($files | Where-Object Name -Like 'deletion_*.rds')
$full = @($files | Where-Object Name -eq 'full.rds')
$latest = $files | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
$validationPath = Join-Path $resultsDir 'validation_report.json'
$scientificallyComplete = $false
if (Test-Path -LiteralPath $validationPath) {
    $validation = Get-Content -Raw -LiteralPath $validationPath | ConvertFrom-Json
    $scientificallyComplete = [bool](
        $validation.actual_deletion_rows -eq $profile.expected_deletion_rows -and
        $validation.actual_dataset_method_rows -eq $profile.expected_dataset_method_rows -and
        $validation.actual_setting_method_summary_rows -eq $profile.expected_setting_method_summary_rows -and
        $validation.duplicate_deletion_keys -eq 0 -and
        $validation.every_completed_cell_has_all_deletions -and
        $validation.every_prediction_comparison_uses_n_test
    )
}
$combinedValidationPath = Join-Path $profile.combined_output_dir 'combined_validation_report.json'
$combinedComplete = $false
if (Test-Path -LiteralPath $combinedValidationPath) {
    $combinedComplete = [bool](
        (Get-Content -Raw -LiteralPath $combinedValidationPath | ConvertFrom-Json).all_checks_pass
    )
}

$effectiveStatus = if (-not $state) {
    'not_started'
} elseif ($scientificallyComplete -and $combinedComplete) {
    'complete_and_merged'
} elseif ($scientificallyComplete) {
    'complete_soft1_waiting_for_or_retrying_merge'
} elseif ($state.Status -eq 'running' -and -not $rActive) {
    'stopped_or_finalizing_check_logs'
} elseif ($rActive -and -not $hostActive) {
    'running_but_host_missing'
} else { $state.Status }

[pscustomobject]@{
    CheckedAt = (Get-Date -Format o)
    Status = $effectiveStatus
    MainExperimentActive = $rActive
    HostActive = $hostActive
    RProcessId = if ($state) { $state.RProcessId } else { $null }
    Workers = if ($state) { $state.Workers } else { $null }
    LastHostHeartbeat = if ($state) { $state.LastHeartbeat } else { $null }
    TemporaryKeepAwake = [bool]($hostActive -and $state.TemporaryKeepAwake)
    PauseRequested = (Test-Path -LiteralPath (Join-Path $resultsDir 'control\pause.request.json'))
    FullCheckpoints = $full.Count
    FullCheckpointTarget = 120
    DeletionCheckpoints = $deletions.Count
    DeletionTarget = $profile.expected_deletion_rows
    CountPercentNotTimePercent = [math]::Round(
        100 * $deletions.Count / $profile.expected_deletion_rows, 2
    )
    LatestCheckpoint = if ($latest) { $latest.LastWriteTime.ToString('o') } else { $null }
    Soft1ScientificValidationPassed = $scientificallyComplete
    CombinedNineMethodValidationPassed = $combinedComplete
    OutputDirectory = $resultsDir
    FutureCombinedOutputDirectory = [string]$profile.combined_output_dir
} | Format-List

if ($state -and (Test-Path -LiteralPath $state.StandardError)) {
    Write-Output 'Recent run messages:'
    Get-Content -LiteralPath $state.StandardError -Tail 12
}
if ($state -and $state.PostProcess -and
    (Test-Path -LiteralPath $state.PostProcess.StandardError)) {
    Write-Output 'Recent merge messages:'
    Get-Content -LiteralPath $state.PostProcess.StandardError -Tail 12
}
