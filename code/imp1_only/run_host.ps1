param(
    [ValidateRange(1, 16)][int]$Workers = 8,
    [ValidateRange(0, 168)][double]$MaxHours = 0,
    [switch]$AttachExisting
)

$ErrorActionPreference = 'Stop'
$runRoot = $PSScriptRoot
$profile = Get-Content -LiteralPath (Join-Path $runRoot 'run_profile.json') -Raw | ConvertFrom-Json
$codeDir = Join-Path $runRoot 'code'
$resultsDir = Join-Path $runRoot 'results'
$logsDir = Join-Path $runRoot 'logs'
$statePath = Join-Path $runRoot 'process_state.json'
$utf8 = New-Object Text.UTF8Encoding($false)
$lock = $null
$awakeEnabled = $false
$rProcess = $null
$attachedProcess = $null
$state = $null

function Save-State($Object) {
    $tmp = Join-Path $runRoot ('state_' + [Guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($tmp, ($Object | ConvertTo-Json -Depth 12), $utf8)
    if (Test-Path -LiteralPath $statePath) {
        Copy-Item -LiteralPath $statePath -Destination (Join-Path $runRoot 'process_state.previous.json') -Force
    }
    Move-Item -LiteralPath $tmp -Destination $statePath -Force
}

function Test-ScientificCompletion {
    $validationPath = Join-Path $resultsDir 'validation_report.json'
    if (-not (Test-Path -LiteralPath $validationPath)) { return $false }
    $v = Get-Content -LiteralPath $validationPath -Raw | ConvertFrom-Json
    return [bool](
        $v.actual_deletion_rows -eq $profile.expected_deletion_rows -and
        $v.actual_dataset_method_rows -eq $profile.expected_dataset_method_rows -and
        $v.actual_setting_method_summary_rows -eq $profile.expected_setting_method_summary_rows -and
        $v.duplicate_deletion_keys -eq 0 -and
        $v.every_completed_cell_has_all_deletions -and
        $v.every_prediction_comparison_uses_n_test
    )
}

function Invoke-Postprocess {
    $script = Join-Path $runRoot $profile.postprocess_script
    if (-not (Test-Path -LiteralPath $script)) { throw "Postprocess script is missing: $script" }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $outLog = Join-Path $logsDir "merge_$stamp.stdout.log"
    $errLog = Join-Path $logsDir "merge_$stamp.stderr.log"
    $arguments = @(
        '--vanilla', $script,
        '--six-results', [string]$profile.previous_results_dir,
        '--soft1-results', $resultsDir,
        '--output-dir', [string]$profile.combined_output_dir
    )
    $quoted = ($arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $process = Start-Process -FilePath $profile.rscript -ArgumentList $quoted `
        -WindowStyle Hidden -WorkingDirectory $runRoot `
        -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru
    $process.WaitForExit()
    return [ordered]@{
        ExitCode = $process.ExitCode
        EndedAt = (Get-Date -Format o)
        StandardOutput = $outLog
        StandardError = $errLog
        CombinedOutputDirectory = [string]$profile.combined_output_dir
    }
}

try {
    $lock = [IO.File]::Open((Join-Path $runRoot 'run.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    if (Test-Path -LiteralPath $statePath) {
        $old = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        if ($old.RProcessId) {
            $oldProcess = Get-Process -Id ([int]$old.RProcessId) -ErrorAction SilentlyContinue
            if ($oldProcess -and $oldProcess.ProcessName -eq 'Rscript' -and
                $oldProcess.StartTime.ToUniversalTime().Ticks -eq ([DateTimeOffset]$old.RStartTimeUtc).UtcDateTime.Ticks) {
                if ($AttachExisting) { $attachedProcess = $oldProcess }
                else { throw 'An R process from this run is still alive. Refusing to start a second writer.' }
            }
        }
    }
    if ($AttachExisting -and -not $attachedProcess) { throw 'No matching live R process to attach.' }
    if (-not (Test-Path -LiteralPath $profile.rscript)) { throw 'Configured Rscript executable is missing.' }
    [IO.Directory]::CreateDirectory($resultsDir) > $null
    [IO.Directory]::CreateDirectory($logsDir) > $null
    $env:LC_ALL = 'C'
    $env:OMP_NUM_THREADS = '1'
    $env:OPENBLAS_NUM_THREADS = '1'
    $env:MKL_NUM_THREADS = '1'

    $codeHashes = @(Get-ChildItem -LiteralPath $codeDir -Recurse -File | ForEach-Object {
        $hashStream = [IO.File]::OpenRead($_.FullName)
        $hasher = [Security.Cryptography.SHA256]::Create()
        try { $hexHash = [BitConverter]::ToString($hasher.ComputeHash($hashStream)).Replace('-', '') }
        finally { $hashStream.Dispose(); $hasher.Dispose() }
        [pscustomobject]@{
            File = $_.FullName.Substring($codeDir.Length + 1)
            SHA256 = $hexHash
        }
    })
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    [IO.File]::WriteAllText((Join-Path $logsDir "code_hashes_$stamp.json"),
        ($codeHashes | ConvertTo-Json -Depth 4), $utf8)

    $pausePath = Join-Path $resultsDir 'control\pause.request.json'
    if (-not $attachedProcess -and (Test-Path -LiteralPath $pausePath)) {
        Remove-Item -LiteralPath $pausePath
    }

    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class SoftOneExperimentAwakeState {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint SetThreadExecutionState(uint flags);
}
'@
    $continuous = [Convert]::ToUInt32('80000000', 16)
    if ([SoftOneExperimentAwakeState]::SetThreadExecutionState($continuous -bor [uint32]1) -eq 0) {
        throw 'Could not activate temporary automatic-sleep prevention.'
    }
    $awakeEnabled = $true

    $rArgs = @(
        '--vanilla', (Join-Path $codeDir 'run_main.R'),
        '--replicates', $profile.replicates,
        '--settings', $profile.settings,
        '--methods', ($profile.methods -join ','),
        '--workers', "$Workers",
        '--output-dir', $resultsDir
    )
    if ($MaxHours -gt 0) {
        $rArgs += '--max-hours'
        $rArgs += $MaxHours.ToString([Globalization.CultureInfo]::InvariantCulture)
    }
    $stdout = Join-Path $logsDir "run_$stamp.stdout.log"
    $stderr = Join-Path $logsDir "run_$stamp.stderr.log"
    $quotedRArgs = ($rArgs | ForEach-Object { '"' + $_ + '"' }) -join ' '
    if ($attachedProcess) {
        $rProcess = $attachedProcess
        $stdout = $old.StandardOutput
        $stderr = $old.StandardError
        $rArgs = $old.Arguments
        $Workers = $old.Workers
        $MaxHours = $old.MaxHours
    } else {
        $rProcess = Start-Process -FilePath $profile.rscript -ArgumentList $quotedRArgs `
            -WindowStyle Hidden -WorkingDirectory $codeDir `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    }

    $state = [ordered]@{
        Status = 'running'
        StartedAt = $rProcess.StartTime.ToString('o')
        HostProcessId = $PID
        RProcessId = $rProcess.Id
        RStartTimeUtc = $rProcess.StartTime.ToUniversalTime().ToString('o')
        Workers = $Workers
        MaxHours = $MaxHours
        TemporaryKeepAwake = $true
        OutputDirectory = $resultsDir
        StandardOutput = $stdout
        StandardError = $stderr
        Arguments = $rArgs
        LastHeartbeat = (Get-Date -Format o)
        EndedAt = $null
        ExitCode = $null
        PostProcess = $null
    }
    Save-State $state
    Write-Output "Running R PID $($rProcess.Id) with $Workers workers; output: $resultsDir"

    while (-not $rProcess.WaitForExit(15000)) {
        $state.LastHeartbeat = Get-Date -Format o
        Save-State $state
    }
    $rProcess.WaitForExit()
    if (-not $attachedProcess) { $state.ExitCode = $rProcess.ExitCode }
    $state.EndedAt = Get-Date -Format o
    $state.LastHeartbeat = $state.EndedAt
    $state.TemporaryKeepAwake = $false

    $scientificallyComplete = Test-ScientificCompletion
    if (Test-Path -LiteralPath $pausePath) {
        $state.Status = 'paused'
    } elseif ($scientificallyComplete) {
        $state.Status = 'complete'
    } elseif ($null -ne $state.ExitCode -and $state.ExitCode -ne 0) {
        $state.Status = 'failed'
    } elseif (-not (Test-Path -LiteralPath (Join-Path $resultsDir 'validation_report.json'))) {
        $state.Status = 'incomplete_missing_validation'
    } else {
        $state.Status = 'incomplete_check_validation'
    }
    Save-State $state

    if ($state.Status -eq 'complete') {
        $state.Status = 'merging_with_six_method_results'
        Save-State $state
        $post = Invoke-Postprocess
        $state.PostProcess = $post
        if ($post.ExitCode -eq 0 -and
            (Test-Path -LiteralPath (Join-Path $profile.combined_output_dir 'combined_validation_report.json'))) {
            $combinedValidation = Get-Content -Raw -LiteralPath `
                (Join-Path $profile.combined_output_dir 'combined_validation_report.json') | ConvertFrom-Json
            if ($combinedValidation.all_checks_pass) {
                $state.Status = 'complete_and_merged'
            } else {
                $state.Status = 'complete_merge_failed_validation'
            }
        } else {
            $state.Status = 'complete_merge_failed'
        }
        $state.LastHeartbeat = Get-Date -Format o
        Save-State $state
    }
    Write-Output "R ended: $($state.Status); exit code: $($state.ExitCode)"
} catch {
    if ($state) {
        $state.HostError = $_.Exception.Message
        $state.LastHeartbeat = Get-Date -Format o
        $liveR = Get-Process -Id ([int]$state.RProcessId) -ErrorAction SilentlyContinue
        if ($liveR) { $state.Status = 'running_but_host_error' }
        elseif (Test-ScientificCompletion) { $state.Status = 'complete_host_error' }
        else { $state.Status = 'host_error' }
        Save-State $state
    }
    Write-Error $_
} finally {
    if ($awakeEnabled) {
        [void][SoftOneExperimentAwakeState]::SetThreadExecutionState(
            [Convert]::ToUInt32('80000000', 16)
        )
    }
    if ($lock) { $lock.Dispose() }
}
