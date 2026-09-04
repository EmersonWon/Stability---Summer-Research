# Soft implementation 1 formal run start report

- Started: 2026-09-04 01:19:09 (Asia/Shanghai)
- R process: PID 28148 at launch (temporary identifier; use status.ps1 for current truth)
- Host process: PID 25128 at launch
- R executable: C:\Program Files\R\R-4.6.0\bin\x64\Rscript.exe
- Workers: 8 PSOCK workers; ranger threads per worker: 1
- Scope: settings 1-4, replicates 1-10, Soft implementation 1 at nu=0.005/0.025/0.1
- Target: 60,000 deletion checkpoints, 120 dataset rows, 12 setting-method rows
- Configuration fingerprint: 50b52c479c7e3621355bf97fa40e4e3d9799f831ed8e97de49c8ded6f5301f29
- Fresh fit: no previous model checkpoints were copied or reused
- Matched design: same prespecified config, replicate seeds, data/test generation, mask uniforms and learner-seed schedule as the validated six-method run
- Automatic postprocess: after strict Soft 1 validation, merge with full_R10_no_soft1_20260902/results and validate the nine-method combined output

Pre-launch checks:

1. R 4.6.0 executable and required packages were available.
2. PowerShell launcher and status scripts parsed successfully.
3. The merge script parsed successfully in R.
4. A two-worker Soft 1 smoke run completed all three nu values with 60/3/3 rows, zero duplicate keys, all deletions complete and correct test prediction counts.
5. C: drive had approximately 458 GB free before launch.
6. After launch, a miniature two-source nine-method merge completed 180/9/9 rows,
   created all comparison tables and five figure files, and passed every combined validation check.

The formal run was rechecked at 2026-09-04 01:29. It was active with both host and R processes alive, heartbeat current, 8 full checkpoints and 79 deletion checkpoints already saved.
