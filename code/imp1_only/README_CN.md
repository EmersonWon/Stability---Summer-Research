# Soft implementation 1 正式实验（R=10，4 settings）

这个目录只运行 Soft implementation 1 的三个平滑参数：nu=0.005、0.025、0.1。
它与已经完成并验证的六方法实验使用同一套正式 simulation design、十个 replicate
seeds、测试样本、mask uniforms 和 learner seeds，因此将来 Soft 1 与 Soft 2 的比较是
matched comparison。

## 运行范围

- 4 个 settings × 10 个 Monte Carlo replicates × 3 个方法；
- 每个 dataset-method 拟合一次 full data 和 500 个 leave-one-out 数据集；
- 目标为 120 个 full checkpoints、60,000 条 deletion checkpoints、
  120 行 dataset_results.csv 和 12 行 setting_method_summary.csv；
- 每次 Soft 1 预测包含 25 个 masks；每个 mask 训练一个 250-tree random forest，
  所以每个 full/deleted predictor 实际训练 6,250 棵树；
- 默认使用 8 个 Windows PSOCK workers；每个 ranger 拟合只用 1 个线程，避免嵌套抢核。

## 最简单的操作

- 双击 view_status.cmd：只读查看当前状态；
- 双击 request_pause.cmd：请求安全暂停，已完成的 fit 会保存在 checkpoint；
- 双击 start_or_resume.cmd：首次启动或暂停后续算，默认 8 workers。

PowerShell 启动：

    Set-Location 'C:\Users\CHWon\Documents\Codex\2026-08-29\x20-github-plugin-github-openai-curated\outputs\full_R10_soft1_only_20260904'
    .\start_or_resume.ps1 -Workers 8

设置安全工作时段：

    .\start_or_resume.ps1 -Workers 8 -MaxHours 4

R=10 是统计重复次数；Workers=8 是同时运行的 R 工作进程数，两者不能混同。
进度百分比是 checkpoint 数量百分比，不是耗时百分比，因为不同 setting 和 nu 的
mask 大小会影响单次拟合时间。

## 完成后的自动合并

Soft 1 严格验证通过后，run_host.ps1 会自动运行 merge_with_previous.R，与
full_R10_no_soft1_20260902/results 合并。最终九方法目录是：

    ..\combined_R10_all9_20260904

合并程序要求两次运行的 configuration fingerprint 与 dense coefficient vector
完全一致，并核对 180,000 / 360 / 36 的行数、九种方法、重复键、500 个 deletion、
5,000 个共同测试点和每格 10 个 replicates。任何检查失败都不会伪装成完成。

状态含义：

- running：正在拟合；
- paused：已经在 checkpoint 安全边界暂停；
- complete_soft1_waiting_for_or_retrying_merge：Soft 1 有效，但合并尚未完成；
- complete_and_merged：Soft 1 与九方法合并均验证通过；
- failed / host_error：需要查看状态页列出的日志。

