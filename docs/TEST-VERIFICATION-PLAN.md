# OpenTenBase 全面测试验证计划

> 创建时间：2026-05-30
> 版本：v5.0-p9
> 状态：执行中

---

## 一、测试范围

### 1.1 架构覆盖

| 架构 | 状态 | 备注 |
|------|------|------|
| x86_64 | ✅ 已验证 | 8 个发行版 CI 通过 |
| aarch64 | ✅ 已验证 | openEuler CI 通过 |

### 1.2 发行版覆盖

| 发行版 | x86_64 | aarch64 | 安装测试 | 功能测试 |
|--------|--------|---------|----------|----------|
| Ubuntu 20.04 (focal) | ✅ | - | ✅ | ✅ |
| Ubuntu 22.04 (jammy) | ✅ | - | ✅ | ✅ |
| Ubuntu 24.04 (noble) | ✅ | - | ✅ | ✅ |
| Ubuntu 25.04 (plucky) | ✅ | - | ✅ | ✅ |
| Debian 11 (bullseye) | ✅ | - | ✅ | ✅ |
| Debian 12 (bookworm) | ✅ | - | ✅ | ✅ |
| Debian 13 (trixie) | ✅ | - | ✅ | ✅ |
| openEuler 22.03 | ✅ | ✅ | ✅ | ✅ |
| CentOS Stream 8 | ✅ | - | ✅ | ✅ |
| CentOS Stream 9 | ✅ | - | ✅ | ✅ |
| Rocky Linux 8 | ✅ | - | ✅ | ✅ |
| Rocky Linux 9 | ✅ | - | ✅ | ✅ |
| AlmaLinux 8 | ✅ | - | ✅ | ✅ |
| AlmaLinux 9 | ✅ | - | ✅ | ✅ |
| Fedora 40 | ✅ | - | ✅ | ✅ |

---

## 二、测试类型

### 2.1 构建测试（CI 自动）

| 测试项 | 工作流 | 频率 | 状态 |
|--------|--------|------|------|
| DEB 包构建 | build-multi.yml | 每次 tag | ✅ |
| RPM 包构建 | build-rpm.yml | 每次 tag | ✅ |
| ARM64 RPM 构建 | build-rpm.yml | 每次 tag | ✅ |
| Docker 镜像构建 | docker-publish.yml | 手动/Release | ✅ |

### 2.2 安装测试（CI 自动）

| 测试项 | 工作流 | 验证内容 | 状态 |
|--------|--------|----------|------|
| 包安装 | test-all.yml | apt/dnf install 成功 | ✅ |
| 依赖满足 | test-all.yml | 无缺失依赖 | ✅ |
| 服务初始化 | test-all.yml | opentenbase-ctl init | ✅ |
| 服务启动 | test-all.yml | opentenbase-ctl start | ✅ |
| 连接测试 | test-all.yml | psql 连接成功 | ✅ |

### 2.3 功能测试（CI 自动）

| 测试套件 | 测试数 | 内容 | 状态 |
|----------|--------|------|------|
| 基础 SQL | 1 | CREATE TABLE, INSERT, SELECT | ✅ |
| 事务测试 | 6 | COMMIT/ROLLBACK, 隔离级别, SAVEPOINT | ✅ |
| 连接池 | 6 | 并发连接, 池耗尽, 重载 | ✅ |
| 数据类型 | 7 | int, text, jsonb, timestamp, array | ✅ |
| 性能基准 | 6 | 批量 INSERT, JOIN, 索引 | ✅ |
| 故障恢复 | 7 | 节点状态, 压力测试, 数据一致性 | ✅ |
| **总计** | **31** | | ✅ |

### 2.4 手动测试（服务器实测）

| 测试项 | 服务器 | 结果 | 备注 |
|--------|--------|------|------|
| 安装 | 47.108.249.115 | ✅ | Alibaba Cloud Linux 3 |
| 集群初始化 | 47.108.249.115 | ✅ | GTM + CN + DN |
| SQL 验证 | 47.108.249.115 | ✅ | CRUD 操作 |
| 性能测试 | 47.108.249.115 | ✅ | 基准测试完成 |
| ARM64 安装 | hdspace otb_ubu_test | ✅ | openEuler 2.0 aarch64, 4vCPU 7.2GB |
| ARM64 集群初始化 | hdspace otb_ubu_test | ✅ | opentenbase-ctl init + start |
| ARM64 SQL 验证 | hdspace otb_ubu_test | ✅ | DISTRIBUTE BY SHARD, INSERT, SELECT |
| ARM64 节点注册 | hdspace otb_ubu_test | ✅ | pgxc_node: gtm_master + coord1 + dn1 |

---

## 三、测试环境

### 3.1 CI 环境

| 环境 | Runner | 平台 | 备注 |
|------|--------|------|------|
| GitHub Actions | ubuntu-latest | amd64 | 主构建平台 |
| GitHub Actions | ubuntu-latest + QEMU | arm64 | ARM64 模拟构建 |
| Docker | 各发行版容器 | 多平台 | 隔离测试 |

### 3.2 手动测试环境

| 服务器 | IP | 系统 | 配置 | 用途 |
|--------|-----|------|------|------|
| 云服务器 | 47.108.249.115 | Alibaba Cloud Linux 3 | 2核1.8GB | 安装验证（内存不足，OOM） |
| hdspace otb_ubu_test | hdspace tunnel | openEuler 2.0 aarch64 | 4vCPU 7.2GB | ARM64 全功能验证 |
| hdspace DevEnvVM | hdspace tunnel | openEuler 2.0 aarch64 | 4vCPU 8GB | ARM64 备用环境 |

---

## 四、测试结果汇总

### 4.1 CI 测试结果

| 工作流 | 最新运行 | 结果 | 详情 |
|--------|----------|------|------|
| build-multi.yml | 26688996831 | ✅ 7/7 DEB | 全部成功 |
| build-rpm.yml | 26691145759 | ✅ 8/8 x86_64 + 1/1 arm64 | 全部成功 |
| test-all.yml | 26683489025 | ✅ 14/14 distros | 31/31 测试通过 |
| docker-publish.yml | 26689388947 | ✅ 成功 | GHCR 发布成功 |

### 4.2 手动测试结果

| 测试 | 结果 | 备注 |
|------|------|------|
| 服务器安装 | ✅ | Ubuntu 24.04 |
| 节点注册 bug 修复 | ✅ | template1 方案 |
| ARM64 hdspace 部署 | ✅ | openEuler 2.0 aarch64, 全流程通过 |
| ARM64 分布式表 | ✅ | DISTRIBUTE BY SHARD + INSERT/SELECT |
| Cloudflare CDN | ✅ | apt.blackevil217.com |
| Docker 镜像 | ✅ | ghcr.io 发布 |

---

## 五、已知问题与修复

| 问题 | 状态 | 解决方案 |
|------|------|----------|
| opentenbase-ctl 节点注册失败 | ✅ 已修复 | -d template1 替代 -d postgres |
| Rocky/Alma ARM64 构建失败 | ⏳ 待修复 | QEMU 依赖问题 |
| /var/run 符号链接冲突 | ✅ 已修复 | Dockerfile 只复制 var/lib/ |
| Docker 容器输出隔离 | ✅ 已修复 | volume mount |
| 1.8GB 服务器 OOM | ⚠️ 已知限制 | 最低需要 3GB RAM，脚本已加入内存自动检测 |
| wait_for_port IPv4-only | ✅ 已修复 | 改用 `ss -tlnp` 检测（支持 IPv6 dual-stack） |
| gtm_host/gtm_port 非法 GUC | ✅ 已修复 | 使用 CREATE NODE SQL 注册节点 |
| max_coordinators 非法 GUC | ✅ 已修复 | 从配置中移除 |
| ARM64 RPM 未发布到 CDN | ✅ 已修复 | 修复 build-repo.sh glob 模式，触发 deploy-repo 重新部署 |
| v2.6.0/v2.5.0 未在 CI 测试 | ✅ 已修复 | test-all.yml 多版本矩阵（v5.0 + v2.6.0 + v2.5.0） |
| APT/RPM 仓库不索引 v2.6.0/v2.5.0 | ✅ 已修复 | APT component 选择器（main/v2.6/v2.5）+ RPM createrepo_c 原生支持 |
| hdspace GitHub 下载慢 | ⚠️ 已知限制 | ~20KB/s，9.5MB RPM 需 ~8 分钟 |

---

## 六、后续计划

### 6.1 短期（1周）

| 任务 | 优先级 | 状态 | 说明 |
|------|--------|------|------|
| 多版本 CI 测试 | P0 | ✅ 已完成 | test-all.yml 多版本矩阵（v5.0 + v2.6.0 + v2.5.0） |
| 多版本仓库索引 | P0 | ✅ 已完成 | APT component 选择器 + RPM createrepo_c |
| 一键部署脚本 | P0 | 进行中 | setup-cluster.sh 交互式部署 |
| Rocky/Alma ARM64 修复 | P2 | ⏳ 待修复 | QEMU 依赖问题，需 ARM64 服务器调试 |
| 跨机器多节点部署 | P1 | TODO | 支持分布式集群 |
| 文档完善 | P2 | TODO | 安装/配置/故障排查指南 |

### 6.2 中期（1月）

| 任务 | 优先级 | 说明 |
|------|--------|------|
| 性能优化 | P1 | 查询性能基准测试 |
| 监控集成 | P2 | Prometheus/Grafana |
| 安全审计 | P2 | 配置安全检查 |

### 6.3 长期（3-6月）

| 任务 | 优先级 | 说明 |
|------|--------|------|
| 合入官方仓库 | P1 | 代码审查、文档完善 |
| 多版本升级测试 | P1 | v5.0 → v6.0 升级路径 |
| 生产环境验证 | P0 | 真实负载测试 |

---

## 七、测试脚本

### 7.1 自动化测试命令

```bash
# 运行全部测试
./test/run-advanced-tests.sh

# 运行单个测试套件
./test/advanced/test_transactions.sh
./test/advanced/test_connection_pool.sh
./test/advanced/test_data_types.sh
./test/advanced/test_performance.sh
./test/advanced/test_failover.sh

# 触发 CI 测试
gh workflow run test-all.yml
```

### 7.2 手动验证命令

```bash
# 安装验证
curl -sSL https://apt.blackevil217.com/setup-apt.sh | sudo bash
sudo apt install opentenbase

# 集群验证
opentenbase-ctl init
opentenbase-ctl start
opentenbase-ctl status

# SQL 验证
psql -h 127.0.0.1 -p 5432 -U opentenbase -d postgres -c "
  CREATE TABLE test (id int, name text) DISTRIBUTE BY SHARD(id);
  INSERT INTO test VALUES (1, 'hello');
  SELECT * FROM test;
"
```

---

**计划版本**: 1.1
**最后更新**: 2026-05-31
**维护者**: muzimu217
