# pgvector 项目一/项目二 AI 可复现工作流 SOP

## 1. 目标

本 SOP 用于指导 AI Agent 在 OpenTenBase/TDSQL-A pgvector 方向完成两类任务：

- 项目一：向量检索插件 pgvector 查询性能优化。
- 项目二：向量索引构建与诊断能力增强。

该流程强调可复现、可扩展、可审查。它不固定某一组数据量、服务器、参数或优化点，而是规定每个阶段必须产生的证据、决策门和交付物，让不同 AI 在不同环境中也能稳定产出可比较结果。

## 2. 核心原则

1. 先建立基线，再谈优化。
2. 所有性能结论必须同时报告正确性或 recall。
3. 所有 benchmark 必须保存命令、环境、原始数据、图表和 `EXPLAIN` 证据。
4. 参数不写死，用矩阵生成：`rows`、`dims`、`lists`、`probes`、`metrics` 均可按环境预算调整。
5. 每个阶段都有退出条件，未通过则回到上一个阶段，而不是强行写结论。
6. 报告只写已经验证的内容，规划内容必须明确标记为下一阶段计划。

## 3. 输入

AI Agent 启动前需要收集：

| 输入 | 示例 | 可替换性 |
| --- | --- | --- |
| 仓库地址 | `OpenTenBase-Packages`、OpenTenBase 源码仓库 | 可替换为 fork 或上游 |
| 服务器 | SSH 远程开发环境 | 可替换为本地、云服务器、容器 |
| 数据库版本 | OpenTenBase 5.0 | 可替换为其他兼容版本 |
| 插件目录 | `contrib/pgvector` | 若目录不同，先定位源码 |
| 项目方向 | 项目一或项目二 | 可单独执行，也可串联 |
| 资源预算 | CPU、内存、磁盘、运行时长 | 决定 benchmark 矩阵规模 |

## 4. 通用阶段

### 阶段 0：环境画像

执行内容：

- 确认仓库分支、远程地址、未提交改动。
- 确认服务器可连接。
- 确认安装方式：APT、源码编译、Docker、已有集群。
- 记录 CPU、内存、磁盘、OS、OpenTenBase 版本。
- 验证 `CREATE EXTENSION vector`。

产物：

```text
docs/<project>/environment.md
```

退出条件：

- 能执行基础向量插入和距离查询。
- 能确定后续 benchmark 使用的数据库连接参数。

失败处理：

- Docker 不可用时切换到 APT 或源码安装。
- APT 源异常时记录坏源并隔离处理。
- 磁盘不足时先清理日志或降低 benchmark 规模。

### 阶段 1：基线工具准备

执行内容：

- 在 `contrib/pgvector/bench/` 建立 benchmark 工具。
- 工具必须支持环境变量配置，而不是写死参数。
- 生成 deterministic 数据，保存 CSV 结果。
- 自动输出 `EXPLAIN` plan。
- 对 exact 查询和 approximate 查询分别计时。

最低参数集合：

```text
ROWS
DIMS
QUERIES
TOPK
LISTS
PROBES_LIST
METRICS
MAINTENANCE_WORK_MEM
OUTPUT
PLAN_OUTPUT
```

产物：

```text
patches/pgvector-ivfflat-benchmark-tools.patch
docs/<project>/benchmark-data/*.csv
docs/<project>/benchmark-data/*_plans.txt
```

退出条件：

- `bash -n` 或等效语法检查通过。
- 小规模 smoke benchmark 通过。
- 至少一个 metric 的 plan 显示 `Index Scan using ... ivfflat ...`。

### 阶段 2：正式 benchmark 矩阵

AI 不应固定某一组参数，而应根据资源预算选择矩阵。

推荐生成规则：

| 环境 | rows | dims | queries | lists | probes |
| --- | ---: | ---: | ---: | ---: | --- |
| 低配 | 10000-50000 | 64-128 | 10-30 | `sqrt(rows)` 附近 | `1, 5, 10, 50, lists` |
| 中配 | 100000-300000 | 128-384 | 30-100 | `sqrt(rows) * 2-4` | `1, 5, 10, 50, 100, lists/2, lists` |
| 高配 | 1000000+ | 384-768 | 100+ | 分多档 | 按 recall 目标自适应 |

必须覆盖：

```text
l2
ip
cosine
```

退出条件：

- 每个 metric 至少 5 档 probes。
- 每个 metric 有 recall/latency 曲线。
- 每个 metric 有 IVFFlat Index Scan 证据。

失败处理：

- 索引构建内存不足：提高 `MAINTENANCE_WORK_MEM` 或降低 `LISTS`。
- recall 全为 1.0：增大 rows/lists，降低 probes，或引入更难的数据分布。
- 查询没有走索引：检查 `ORDER BY` 是否只按距离表达式排序，检查 opclass/operator 是否匹配。

### 阶段 3：数据整理与图表

图表至少包含：

- recall@k vs probes。
- avg latency vs probes。
- p95 latency vs probes。
- exact scan 对照线或表格。

产物：

```text
docs/<project>/figures/pgvector-recall-vs-probes.svg
docs/<project>/figures/pgvector-avg-latency-vs-probes.svg
docs/<project>/figures/pgvector-p95-latency-vs-probes.svg
```

退出条件：

- 图表可解析、非空。
- 图表中的点数与 CSV 行数一致。
- 报告中的数字来自 CSV，不手抄未验证数据。

## 5. 项目一工作流：查询性能优化

### 5.1 目标

在 L2/IP/Cosine 场景下，保证结果正确性和 recall 稳定，同时降低查询耗时或提升吞吐。

### 5.2 执行步骤

1. 建立 IVFFlat benchmark 基线。
2. 确认查询计划走 IVFFlat。
3. 识别 probes 与 recall/latency 的边界。
4. 选择优化候选：
   - 距离计算函数。
   - IVFFlat 扫描路径。
   - tuple fetch 或排序路径。
   - OpenTenBase 分布式执行开销。
5. 使用 profiling 定位热点。
6. 实施低风险代码改动。
7. 复跑同一 benchmark 矩阵。
8. 输出 before/after 对比报告。

### 5.3 决策门

| 决策点 | Go 条件 | No-Go 处理 |
| --- | --- | --- |
| 是否进入 C 代码优化 | baseline 稳定且 plan 正确 | 先修 benchmark |
| 是否接受优化 | recall 不下降，延迟或吞吐改善 | 回滚或改为实验记录 |
| 是否提交 PR | 有测试、报告、复现命令 | 补齐验证 |

### 5.4 交付物

```text
patches/pgvector-ivfflat-benchmark-tools.patch
docs/pgvector-performance-development-report.md
docs/benchmark-data/*.csv
docs/figures/*.svg
优化代码 PR 或实验补丁
```

## 6. 项目二工作流：索引构建与诊断增强

### 6.1 目标

让用户更容易发现“索引建得不合理、召回低、构建慢、内存不足、查询没走索引”等问题，并给出可执行建议。

### 6.2 执行步骤

1. 收集项目一 benchmark 观测数据。
2. 建立诊断对象：
   - 观测表。
   - 参数推荐函数。
   - 低召回风险检测 SQL。
   - 索引构建内存建议 SQL。
3. 覆盖异常场景：
   - `maintenance_work_mem` 不足。
   - `ORDER BY` 写法导致索引失效。
   - `probes` 过低导致 recall 断崖。
   - 数据分布不均导致 recall 波动。
4. 输出诊断报告和调优模板。
5. 将诊断工具纳入 patch 或独立 PR。

### 6.3 推荐函数设计

函数不应只返回一个固定答案，而应返回：

```text
recommended_lists
recommended_probes
estimated_recall
expected_avg_latency_ms
maintenance_work_mem
recommendation_source
risk_level
rationale
```

推荐策略：

- 命中已有观测数据时，返回 measured 推荐。
- 未命中时，返回 heuristic 推荐。
- heuristic 必须提示用户运行 benchmark 复测。

### 6.4 交付物

```text
contrib/pgvector/bench/ivfflat_recommendation.sql
docs/pgvector-optimization-roadmap-engineering-plan.md
docs/pgvector-index-diagnostics-report.md
docs/pgvector-production-tuning-template.md
```

## 7. AI Agent 执行模板

### 7.1 每轮执行前

AI 必须确认：

```text
当前分支
git status
远程仓库
目标项目：项目一或项目二
本轮目标
预期产物
```

### 7.2 每轮执行中

AI 必须保留：

```text
运行命令
输出文件路径
失败原因
修复动作
复验命令
```

### 7.3 每轮执行后

AI 必须输出：

```text
完成了什么
验证了什么
哪些数据可用于报告
哪些结论仍然只是计划
下一步建议
```

## 8. 可扩展节点

以下节点允许替换，避免把流程钉死：

| 节点 | 默认实现 | 可替换实现 |
| --- | --- | --- |
| 数据生成 | deterministic random vectors | clustered、skewed、真实 embedding |
| 指标 | avg/p95/recall@k | QPS、p99、内存峰值、索引构建耗时 |
| 图表 | SVG line charts | PNG、PDF、dashboard |
| 安装方式 | APT | 源码编译、Docker、已有集群 |
| 推荐策略 | measured-first heuristic | 回归模型、网格搜索、贝叶斯优化 |
| profiling | perf | gprof、eBPF、火焰图工具 |
| 报告 | Markdown | PDF、PPT、PR description |

## 9. 禁止事项

- 禁止只报告延迟，不报告 recall。
- 禁止没有 `EXPLAIN` 证据就宣称使用了 IVFFlat。
- 禁止将 smoke benchmark 当正式结论。
- 禁止把某一次服务器上的参数写成普适默认值。
- 禁止把 heuristic 推荐写成确定性能保证。
- 禁止忽略失败场景；失败必须变成诊断能力或风险说明。

## 10. 最终交付包结构

建议项目提交包使用以下结构：

```text
docs/
  benchmark-data/
  figures/
  pgvector-performance-development-report.md
  pgvector-optimization-roadmap-engineering-plan.md
  pgvector-index-diagnostics-report.md
patches/
  pgvector-ivfflat-benchmark-tools.patch
scripts 或 contrib patch/
  benchmark and diagnostics tools
```

## 11. 交付判定

满足以下条件可认为一个项目阶段完成：

- 有代码或工具产物。
- 有原始数据。
- 有图表。
- 有验证命令。
- 有失败场景记录。
- 有可复现报告。
- 有可提交 PR 或 issue。

如果缺少其中任一项，只能标记为“阶段性探索”，不能标记为“完成交付”。

