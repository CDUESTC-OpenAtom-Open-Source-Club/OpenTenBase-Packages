# pgvector 优化路径与工程卓越计划报告

## 1. 定位

本项目以“项目一：向量检索插件 pgvector 查询性能优化”为主线，目标不是只完成一次性能测试，而是形成一套可复用的 OpenTenBase/TDSQL-A 向量检索工程方法：可复现 benchmark、可解释参数推荐、可观测诊断、可验证内核优化和可提交开源 PR。

当前已完成第一阶段工程基线：

- OpenTenBase 5.0 远程环境安装与 pgvector 可用性验证。
- L2、Inner Product、Cosine 三类 IVFFlat benchmark。
- 100000 行、128 维、30 查询的正式 recall/latency 数据。
- `EXPLAIN` 验证三类查询均走 IVFFlat Index Scan。
- 参数推荐函数 `recommend_ivfflat_params`。
- 安装包日志轮转修复，避免 benchmark 或单机测试写满根分区。

## 2. 评审关注点对齐

| 评审关注点 | 本项目回应 |
| --- | --- |
| 正确性 | exact scan 作为 recall 对照；每个 metric 输出 plan 证据 |
| 性能收益 | 通过 probes 曲线明确低延迟/高召回边界，为后续优化提供基线 |
| 工程可复现 | benchmark 脚本、CSV、SVG、plan 文件全部入库 |
| 可推广性 | 参数推荐函数把实测数据沉淀为可执行工具 |
| 开源贡献 | benchmark 工具补丁、安装包日志修复补丁可拆分提交 PR |

## 3. 参数推荐引擎

第一版推荐逻辑采用“实测优先、启发式兜底”：

1. 如果输入命中已有观测数据，选择满足目标 recall 的最低平均延迟参数。
2. 如果没有观测数据，根据 `row_count`、`dims`、`target_recall`、`metric` 返回保守初始值。
3. 对启发式结果标记 `recommendation_source = heuristic`，要求上线前跑本地 benchmark 复测。

已验证示例：

| 场景 | 输出 |
| --- | --- |
| 100000 行、128 维、Cosine、目标 recall 0.90 | `lists=1000`、`probes=500`、实测 recall 0.9400 |
| 100000 行、128 维、IP、目标 recall 0.90 | `lists=1000`、`probes=1000`、实测 recall 1.0000 |
| 250000 行、256 维、IP、目标 recall 0.95 | `lists=1600`、`probes=1380`、启发式，建议复测 |

后续增强方向：

- 将更多数据规模纳入观测表，例如 10000、50000、200000、1000000 行。
- 增加数据分布标签，例如 uniform、clustered、skewed。
- 将推荐结果扩展为 SQL 诊断视图，提示“召回风险高”“建索引内存不足”“probes 超过合理延迟预算”等问题。

## 4. 内核级性能画像计划

下一阶段需要用 profiling 证明性能瓶颈在哪里，再决定 C 代码优化点。

建议命令：

```bash
perf record -g -- psql -d postgres -c "SET ivfflat.probes = 500; SELECT id FROM ... ORDER BY embedding <=> '[...]' LIMIT 10;"
perf report
```

重点观察：

- 距离计算函数：L2、IP、Cosine 是否占主要 CPU。
- IVFFlat 扫描路径：候选 list 扫描、tuple fetch、排序是否占比高。
- OpenTenBase 分布式路径：Coordinator 转发、Datanode 执行、Remote Fast Query Execution 是否带来额外开销。

可选优化候选：

- 对距离计算路径评估 SIMD 优化空间。
- 对高 `probes` 场景减少不必要的 tuple/materialize 开销。
- 检查 OpenTenBase 并行执行框架能否用于 exact baseline 或大 probes 场景。

## 5. 分布式可观测性计划

向量查询在 OpenTenBase 中不仅是单机索引问题，还涉及 Coordinator、Datanode 和日志/内存资源。

计划补充诊断 SQL：

- 查询是否命中 IVFFlat：自动解析 `EXPLAIN` 或保存 plan 证据。
- 索引构建内存：根据 rows、dims、lists 给出 `maintenance_work_mem` 建议。
- 查询会话资源：记录 Coordinator/Datanode 活跃 SQL、内存和等待状态。
- 日志风险：检测 `/var/log/opentenbase` 大文件，提示启用日志轮转。

本阶段已落地日志轮转修复：

```text
log_rotation_size = '100MB'
log_truncate_on_rotation = on
```

## 6. 极端场景与负向 Benchmark

后续需要补齐“失败也能解释”的测试，而不是只展示理想数据。

建议用例：

| 场景 | 目标 |
| --- | --- |
| 低 `maintenance_work_mem` | 复现 IVFFlat 建索引失败，并验证推荐函数能给出内存建议 |
| 非均匀数据分布 | 检查 IVFFlat 在 clustered/skewed 数据上是否出现低 recall |
| 过低 probes | 自动识别 recall 断崖式下降并给出 probes 提升建议 |
| 高 probes | 判断延迟是否超过 exact scan，避免盲目追求 recall=1.0 |
| 日志风暴 | 验证日志轮转能限制磁盘增长 |

## 7. PR 拆分建议

建议拆成两个开源 PR，降低审查难度：

1. pgvector benchmark/diagnostic PR
   - 新增 `contrib/pgvector/bench/` 工具。
   - 包含 benchmark、plan 输出、recommendation SQL。
   - 说明该工具不改变数据库行为，只用于性能评估和参数诊断。

2. OpenTenBase-Packages 日志安全 PR
   - 修改 `scripts/opentenbase-ctl` 和 `config/opentenbase-ctl`。
   - 增加 PostgreSQL 日志轮转参数。
   - 附带 CloudStudio 实测日志膨胀案例和修复后磁盘占用结果。

## 8. 下一阶段验收标准

| 阶段 | 验收标准 |
| --- | --- |
| 阶段 1：工具完善 | benchmark、recommendation SQL、报告、图表全部可复现 |
| 阶段 2：画像分析 | 输出 perf 热点报告，定位前 3 个 CPU/执行热点 |
| 阶段 3：优化实现 | 至少完成一个 C 代码或执行路径优化实验 |
| 阶段 4：回归验证 | L2/IP/Cosine recall 不下降，延迟或吞吐至少一项改善 |
| 阶段 5：开源交付 | PR、issue、技术报告、使用说明完整闭环 |

## 9. 当前结论

当前项目已经具备正式开源交稿的基础条件：环境可启动、插件可验证、数据可复现、图表可解释、问题可追踪、修复可提交。下一步重点应从“证明能测”转向“证明能改”：通过 profiling 找到热点，并基于本阶段 benchmark 证明优化前后的真实收益。

