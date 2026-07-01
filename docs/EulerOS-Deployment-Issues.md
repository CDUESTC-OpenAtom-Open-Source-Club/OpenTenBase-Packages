# EulerOS 部署问题记录

## 测试环境
- 系统：Huawei Cloud EulerOS 2.0 (aarch64)
- 架构：ARM64
- 测试日期：2026-07-01

## 发现的问题

### 问题 1：sshpass 缺失 ✗ 严重 → 已通过标准化方案解决

**现象**：
```
[src/ssh/remote_ssh.cpp:83] SCP transfer failed with exit code 32512
```

**原因分析**：
- `opentenbase_ctl` 内部使用 `sshpass` 命令进行 SSH 密码认证
- EulerOS 默认仓库没有 `sshpass` 包
- EPEL 仓库也不支持 EulerOS（需要 redhat-release >= 8）

**影响**：
- CN/DN 节点无法通过 SSH 传输文件
- GTM 节点安装成功，但 CN/DN 失败

**标准化解决方案（已集成到脚本）**：

采用**包管理器 → 静态二进制 → 清晰报错**的标准化流程，而非发行版特例补丁：

```
┌─────────────────────────────────────────────────────┐
│            sshpass 能力获取（标准化流程）              │
├─────────────────────────────────────────────────────┤
│  优先级 1：系统包管理器                               │
│     apt-get / dnf / yum / apk                       │
│                                                     │
│  优先级 2：静态二进制下载（通用备选）                  │
│     从 CDN 下载预编译的静态 sshpass                   │
│     支持 x86_64 + aarch64                           │
│     不依赖任何包管理器或 expect                       │
│                                                     │
│  优先级 3：清晰报错                                  │
│     列出缺失能力清单                                 │
│     提供手动安装指引                                 │
│     优雅退出（exit 1）                              │
└─────────────────────────────────────────────────────┘
```

**架构改进**：
- ✅ 移除 expect wrapper（发行版特例补丁）
- ✅ 添加环境能力预检函数（`check_required_capabilities`）
- ✅ 静态二进制作为通用备选方案
- ✅ 清晰的失败处理和手动指引

**静态二进制来源**：
- 主源：`https://repo.blackevil217.com/binaries/sshpass-{arch}`
- 备选：`https://raw.githubusercontent.com/.../binaries/sshpass-{arch}`
- 构建方法见：`binaries/README.md`

**适用场景**：
- EulerOS/openEuler（无 sshpass 包）
- Alpine（无 sshpass 包）
- 精简容器环境（无包管理器）
- 无 root 权限环境（下载静态二进制到用户目录）

**相关代码**：
```
# opentenbase_ctl 内部调用
sshpass -p '<password>' ssh -o StrictHostKeyChecking=no -p <port> ...
```

---

### 问题 2：opentenbase 用户必须 ⚠ 重要

**现象**：
```
Permission denied (publickey,gssapi-keyex,gssapi-with-mic,password)
```

**原因分析**：
- `opentenbase_ctl` 默认使用 `opentenbase` 用户进行 SSH 连接
- opentenbase 用户的 home 目录是 `/var/lib/opentenbase`（不是 `/home/opentenbase`)
- SSH 密钥必须放在 `/var/lib/opentenbase/.ssh/`

**影响**：
- 使用其他用户（如 developer）会导致 SSH 认证失败
- 脚本需要自动创建 opentenbase 用户并配置 SSH

**解决方案**：
1. 在安装脚本中自动创建 opentenbase 用户
2. 配置 `/var/lib/opentenbase/.ssh/` 目录和密钥
3. 在文档中明确说明必须使用 opentenbase 用户

**配置示例**：
```bash
# 正确的 SSH 配置位置
sudo mkdir -p /var/lib/opentenbase/.ssh
sudo ssh-keygen -t rsa -N "" -f /var/lib/opentenbase/.ssh/id_rsa
sudo cat /var/lib/opentenbase/.ssh/id_rsa.pub | sudo tee /var/lib/opentenbase/.ssh/authorized_keys
sudo chown -R opentenbase:opentenbase /var/lib/opentenbase/.ssh
```

---

### 问题 3：端口分配 bug ✗ 严重 → 已上报上游

**现象**：
```
[src/utils/utils.cpp:87] Failed to find available port pair for 127.0.0.1 after 100 attempts
[src/node/node.cpp:1308] Database connection error: invalid port number: "-16777216"
```

**原因分析**：
- `opentenbase_ctl` 在端口检测时返回负数端口（如 `-16777216`）
- 可能是整数溢出或类型转换问题
- 仅在 EulerOS/aarch64 上出现（未在其他平台测试）

**影响**：
- GTM 配置文件生成错误的端口值
- 节点无法正常启动

**对比测试结果**：
- OpenTenBase 2.6.0 (pgxc_ctl)：端口分配正常（GTM 6666, coord 5432, dn1 15432）
- OpenTenBase 5.0 (opentenbase_ctl)：端口为负数（-16777216, -828132608）

**状态**：
- 已确认是 opentenbase_ctl 上游 bug（不是脚本问题）
- 已向官方提交 Issue：https://github.com/OpenTenBase/OpenTenBase/issues/215

**临时解决方案**：
1. 使用 OpenTenBase 2.6.0（pgxc_ctl）版本，无此问题
2. 在配置文件中手动指定端口（绕过自动分配）
3. 等待上游修复

**GTM 配置文件示例**：
```
# 错误的配置
port = -16777216

# 正确的配置
port = 6666
```

---

## 测试结果总结（2026-07-01）

### OpenTenBase 2.6.0 (pgxc_ctl) ✅ 完全成功

一键部署脚本测试通过：
```
curl -sSL https://raw.githubusercontent.com/.../scripts/opentenbase.sh | sudo bash -s -- install --yes --version 2.6.0
```

验证结果：
- ✅ RPM 包安装成功
- ✅ sshpass 安装成功（改进后的脚本）
- ✅ opentenbase 用户 SSH 配置正确
- ✅ GTM 启动正常（port=6666）
- ✅ Coordinator 启动正常（port=5432）
- ✅ Datanode 启动正常（port=15432）
- ✅ 分布式表创建/读写测试通过
- ✅ 分布式架构验证（GTM + CN + DN）

### OpenTenBase 5.0 ✅ 已解决（通过 pgxc_ctl 启动）

**关键发现**：OpenTenBase 5.0 的 RPM 包**同时包含 `pgxc_ctl` 和 `opentenbase_ctl`**，
即 5.0 支持两种启动方式。由于 `opentenbase_ctl` 在 EulerOS/aarch64 上有端口分配 bug，
脚本在检测到 EulerOS/openEuler 时**自动切换到 `pgxc_ctl` 启动 5.0**，完美绕过该 bug。

```
curl -sSL https://raw.githubusercontent.com/.../scripts/opentenbase.sh | sudo bash -s -- install --yes --version 5.0
```

脚本输出会提示：
```
[WARN] 检测到 EulerOS/openEuler 系统
[WARN] opentenbase_ctl 在此平台上有端口分配 bug（已上报 Issue #215）
[INFO] 自动切换到 pgxc_ctl 启动 5.0（兼容且无此问题）
```

验证结果：
- ✅ RPM 包安装成功
- ✅ 自动检测 EulerOS 并切换 pgxc_ctl
- ✅ GTM/Coordinator/Datanode 全部启动
- ✅ 数据库连接成功（OpenTenBase V5.21）
- ✅ 分片映射初始化（4096 条）
- ✅ 分布式表创建/读写测试通过

> **遗留**：`opentenbase_ctl` 的端口分配 bug 仍待上游修复（Issue #215）。在此之前，
> EulerOS/openEuler 用户通过 `pgxc_ctl` 启动 5.0 是推荐方案。

### opentenbase_ctl 端口分配 bug（待上游修复）

确认存在端口分配 bug（已上报上游 Issue #215）：
- GTM port = -16777216（负数）
- Coordinator port = -16777216（负数）
- forward_port = -828132608（负数）

### RPM 卸载注意事项 ⚠️ → 已修复

卸载后发现的问题（已在 uninstall.sh 中修复）：
1. ❌ RPM 卸载不会自动停止集群进程 → ✅ 已添加 pgxc_ctl 停止逻辑
2. ❌ 卸载后有残留目录（/usr/lib/opentenbase/）→ ✅ 已添加自动清理

使用改进后的卸载脚本：
```bash
curl -sSL https://raw.githubusercontent.com/.../scripts/uninstall.sh | sudo bash -s -- --yes --purge
```

卸载验证结果：
- ✅ RPM 包已卸载
- ✅ 进程已停止（0 个）
- ✅ 目录已清理（/usr/lib/opentenbase、/var/lib/opentenbase、/etc/opentenbase）

---

## 其他发现

### RPM 包安装正常 ✓
- GPG key 导入成功（使用 GitHub Pages 源）
- YUM 仓库配置正常
- opentenbase-2.6.0-1.aarch64 安装成功

### GTM 手动启动成功 ✓
- 修复端口配置后，GTM 可以正常启动
- 监听端口 6666 正常

---

## 修复计划

### 已完成的修复（脚本层面）
1. ✅ sshpass 安装改进：包管理器 → 下载 RPM → expect wrapper 备选
2. ✅ opentenbase 用户 SSH 配置自动处理（检测 home 目录位置）
3. ✅ 文档中添加 opentenbase 用户必须的重要声明
4. ✅ 向上游提交 Issue #215（端口分配 bug）

### 待后续处理
1. RPM 卸载流程改进（自动停止集群、清理残留）
2. 等待上游修复 opentenbase_ctl 端口分配 bug

---

## 测试矩阵

| 版本 | 启动方式 | 发行版 | 架构 | 状态 | 备注 |
|------|----------|--------|------|------|------|
| 2.6.0 | pgxc_ctl | HCE 2.0 | aarch64 | ✅ 通过 | 一键部署成功，分布式测试通过 |
| 5.0 | pgxc_ctl（自动） | HCE 2.0 | aarch64 | ✅ 通过 | 脚本自动检测 EulerOS 切换 pgxc_ctl |
| 5.0 | opentenbase_ctl | HCE 2.0 | aarch64 | ❌ Bug | 端口分配负数，Issue #215（已绕过） |
| 2.5.0 | pgxc_ctl | HCE 2.0 | aarch64 | 待测 | - |

---

## 参考链接
- [[opentenbase-packages-repo]]: fork 名带 -1、admin 权限、禁止 AI 署名