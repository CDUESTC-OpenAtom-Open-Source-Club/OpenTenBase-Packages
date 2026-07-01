# EulerOS 部署问题记录

## 测试环境
- 系统：Huawei Cloud EulerOS 2.0 (aarch64)
- 架构：ARM64
- 测试日期：2026-07-01

## 发现的问题

### 问题 1：sshpass 缺失 ✗ 严重 → 已修复

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

**解决方案（已集成到脚本）**：
1. **方案 A（推荐）**：下载 sshpass 二进制 RPM
   ```bash
   # 从 CentOS Vault 下载
   curl -fsSL https://vault.centos.org/7.9.2009/os/aarch64/Packages/sshpass-1.06-2.el7.aarch64.rpm -o /tmp/sshpass.rpm
   rpm -ivh --nodeps /tmp/sshpass.rpm
   ```
2. **方案 B（备选）**：使用 expect wrapper
   - 脚本会自动创建 `/usr/local/bin/sshpass` wrapper
   - 使用 expect 模拟 sshpass 行为

**脚本改进**：
- 优先尝试包管理器安装
- 失败后自动下载 RPM（尝试多个源）
- 最后备选 expect wrapper
- 如果三种方案都失败，脚本报错退出并提示手动安装

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

## 其他发现

### RPM 包安装正常 ✓
- GPG key 导入成功（使用 GitHub Pages 源）
- YUM 仓库配置正常
- opentenbase-5.0-1.aarch64 安装成功

### GTM 手动启动成功 ✓
- 修复端口配置后，GTM 可以正常启动
- 监听端口 6666 正常

---

## 修复计划

### 短期修复（脚本层面）
1. 在 `setup-rpm.sh` 或 `opentenbase.sh` 中：
   - 自动创建 opentenbase 用户
   - 配置 SSH 免密登录（/var/lib/opentenbase/.ssh/）
   - 创建 sshpass wrapper（使用 expect）
   - 检测并修复端口配置问题

### 长期修复（上游反馈）
1. 向 OpenTenBase 团队报告：
   - EulerOS/aarch64 端口分配 bug
   - sshpass 依赖问题
2. 提供 EulerOS 兼容性补丁

---

## 测试矩阵待完成

| 发行版 | 架构 | 状态 | 问题 |
|--------|------|------|------|
| openeuler | aarch64 | 待测 | 本文档记录的问题 |
| el8 | aarch64 | ✗ | 仓库未发布 |
| el9 | aarch64 | 待测 | - |
| openeuler | x86_64 | 待测 | - |
| el8 | x86_64 | ✓ | 已测试（需确认） |
| el9 | x86_64 | 待测 | - |

---

## 参考链接
- [[opentenbase-packages-repo]]: fork 名带 -1、admin 权限、禁止 AI 署名