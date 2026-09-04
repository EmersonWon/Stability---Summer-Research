# 数值实验两阶段新手说明

这份实验可以分成两个性质不同的阶段。最重要的区别是：第一阶段只准备并冻结实验材料；第二阶段才真正训练模型、删数据、计算稳定性并画图。

## 阶段一：准备实验材料和随机化日程

### 输入是什么

输入是 `config.json` 中事先规定的科学设定，包括：

- 4 个数据生成 setting；
- 每个数据集 `n=500`、`p=200`；
- 10 个 Monte Carlo replicates；
- 5,000 个测试点；
- 10 个不同的 replicate seeds 和 1 个 coefficient seed；
- 阈值、三个 `nu`、树数和 mask 数。

### 程序做什么

1. 用 coefficient seed 只抽一次 Setting 4 的系数向量 `theta`，以后十个 replicate 都使用同一个向量。
2. 对每个 replicate 生成四份训练数据和测试数据。Setting 1 与 Setting 4 使用完全相同的 Gaussian `X` 和 `X_test`，但各自生成响应和噪声。
3. 为每个 `(setting, replicate)` 预先生成一张共享的 uniform matrix。之后每个 soft mask 都由同一个 `U[b,j]` 与当前的 `q[j]` 比较得到。
4. 在模型训练之前，预先生成普通森林、soft implementation 1 各个森林和 soft implementation 2 的 learner seeds。
5. 把数据、uniforms、seeds、生成顺序和 RNG 类型保存成 schedule 文件。

### 为什么必须先保存

可以把 schedule 想成“封好并编号的实验材料箱”。完整数据和删去第 `i` 个 observation 的数据都从同一个材料箱取随机数。

如果不这样做，两次 random forest 会因为 bootstrap、节点候选特征等内部随机性而不同。最后观察到的预测差就同时包含：

```text
删除 observation 的影响 + 两次随机森林随机抽样不同的影响
```

我们真正想测的是前一项。因此保存并复用随机化日程是实验设计的一部分，不只是方便复现的工程细节。

### 阶段一的输出

- `config.resolved.json`：本次运行实际采用的配置；
- `dense_theta.json`：固定 `theta`、coefficient seed 和实际的平方范数；
- `schedules/replicate_XXX.rds`：数据、mask uniforms 和 learner seeds；
- `screening_audits/*.rds`：每个 full/LOO 数据的方差、hard 决策、soft 概率以及 mask 重建信息。

阶段一不训练 random forest，因此它主要验证 DGP、seed coupling 和数据尺寸是否正确。

## 阶段二：训练九种方法并测量稳定性

### 先理解一棵树和一个 mask

- 一个 mask 是长度为 `p` 的 0/1 特征开关。例如 `(1,0,1,0)` 表示本次模型只允许看第 1、3 个 feature。mask 本身不会预测 `Y`。
- 一棵 regression tree 是完整的预测器。它利用允许进入的 features 不断做 `X_j < c` 形式的切分，最后在叶节点输出训练响应的平均值。
- 一个 random forest 把许多随机树的预测平均，从而减小单棵树的不稳定性。

### 九种方法分别是什么

1. All-feature RF：所有 200 个 feature 都进入随机森林。
2. Hard screen：每次在当前数据上重算样本方差，只保留 `variance > 1` 的 feature。
3. Frozen hard：只在完整数据上计算一次 hard selected set；所有 LOO 模型都沿用它。
4–6. Soft implementation 1，分别使用三个 `nu`。每个 mask 后训练一个完整的 250-tree forest；25 个 forest 的预测再平均。因此一个方法共有 `25 x 250 = 6,250` 棵树。
7–9. Soft implementation 2，分别使用三个 `nu`。250 棵树各有一个自己的 mask，最后直接平均这 250 棵树；不是 `250 x 250` 棵树。

若某个 mask 一个 feature 都没有选中，程序使用当前训练集 `Y` 的平均值预测，而不是报错。

### full 与 LOO 怎样比较

对一个给定的 setting、replicate 和 method：

1. 在完整数据 `D` 上训练一次，得到测试集预测 `f_D(X*)`；
2. 依次删除第 1 到第 500 个 observation；
3. 每次在 `D minus i` 上重新训练，并在同一批 5,000 个测试点上预测；
4. 使用同一套 mask uniforms 和相应 learner seeds；
5. 计算

```text
Delta_i = 5,000 个测试点上 (full prediction - LOO prediction)^2 的平均
```

如果 `Delta_i` 大，说明删除 observation `i` 后模型改变较大；如果小，说明对这个删除较稳定。

再把 500 个 `Delta_i` 平均，得到这个数据集和方法的 `beta2_hat`。最后把十个 replicate 的 `beta2_hat` 再求平均和标准差，才得到正式表格中的 `mean (SD)`。

### checkpoint 完成什么

每一个 full fit 和每一个 LOO fit 都单独保存为原子 checkpoint。程序只有在一个结果完整写完以后才把它放到正式文件名下。

因此如果电脑重启或运行中断：

- 已完成的 fit 不需要重算；
- 再运行同一个命令会检查相同的 configuration fingerprint；
- 配置相同就跳过已有 checkpoint；
- 配置不同则拒绝混用旧结果。

checkpoint 解决的是“几天或更久的计算如何可靠续跑”，不是改变统计方法。

### `ranger` 和 `data.table` 分别负责什么

`ranger` 是模型计算引擎。它训练树、执行 bootstrap、在节点寻找 split，并产生测试集预测。没有它就不能完成阶段二的模型拟合。

`data.table` 是结果整理引擎。它把大量 deletion checkpoint 合并，按 setting、replicate 和 method 分组，计算 `beta2_hat`、mean、SD，并检查是否缺少或重复 deletion。它不训练模型，也不会改变预测。

## 从文件到结果的完整数据流

```text
config.json
    -> 固定 theta、四种数据、mask uniforms、learner seeds
    -> saved schedules + screening audits
    -> 9 个 full fits + 每个方法 n 个 LOO fits
    -> deletion checkpoints
    -> deletion_results.csv
    -> dataset_results.csv
    -> setting_method_summary.csv
    -> stability_table.csv + 8 张图 + validation_report.json
```

正式实验预期：

- `4 x 10 x 9 x 500 = 180,000` 行 deletion results；
- `4 x 10 x 9 = 360` 行 dataset results；
- `4 x 9 = 36` 行 setting-method summary。

## smoke test 与正式实验的区别

smoke 使用 `n=20`、`p=6`、`N_test=50`、3 棵树和少量 masks。它检查程序能否从生成数据一直跑到表格和图，但 smoke 的数值没有科学解释价值。

```powershell
.\run_with_r460.ps1 run_main.R --smoke --workers 2 --output-dir outputs\main_smoke
```

正式设计的计算量很大。一次 full 或 LOO fit 中，九种方法合计约含 20,250 个 tree components；共有 40 个 setting-replicate blocks，每个 block 有 1 个 full 和 500 个 LOO 数据，因此总量约为 405.8 million tree components。正式启动前应先做一个 `n=500`、单 setting、单 replicate 的计时研究，并确认磁盘空间、散热和可接受的运行时长。

## 如何查看结果

- `validation_report.json`：先看行数、重复键、测试点数量和 checkpoint 数是否全部正确；
- `stability_table.csv`：正式的 mean (SD) 表；
- `deletion_results.csv`：最底层的每次删除结果；
- `figures/histograms_setting_*.png`：观察 `Delta_i` 的整体分布和极端删除；
- `figures/tail_curves_setting_*.png`：观察超过不同阈值的删除比例；
- `plot_data/`：每张图背后的数值，确保图可以审计和重画。
