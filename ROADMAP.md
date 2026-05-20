# OpenTenBase 官方级包仓库规划

[English](ROADMAP.md) | [中文](ROADMAP_zh.md)

## 愿景

为 OpenTenBase 构建一套**长期、稳定、跨发行版、适配未来版本**的「官方级软件打包/分发体系」，像 PostgreSQL、Docker 那样，给 OpenTenBase 做一套**可长期维护、自动更新、多系统兼容**的包仓库。

---

## 长期目标

### 核心目标

1. **支持 Debian / Ubuntu 全系列**（未来扩展 RHEL/CentOS/Fedora）
2. **支持 OpenTenBase 自身多版本并存**（v5.0 / v6.0 / 开发版）
3. **自动构建、自动签名、自动发布**，用户一行命令安装
4. **长期可维护**，项目更新不用重新造轮子
5. **符合 Linux 发行版标准**，可直接贡献给官方

### 用户体验目标

```bash
# 用户安装方式（极致友好）
curl -sSL https://opentenbase.org/repo/setup.sh | sudo bash
sudo apt install opentenbase

# 或指定版本
sudo apt install opentenbase-5.0
```

---

## 技术架构

### 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                    OpenTenBase 包仓库                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐   │
│  │  Ubuntu PPA  │    │  Debian Repo │    │  RPM Repo    │   │
│  │  20.04/22.04 │    │  11/12/13    │    │  RHEL/CentOS │   │
│  │  24.04       │    │              │    │  Rocky/Fedora│   │
│  └──────────────┘    └──────────────┘    └──────────────┘   │
│           │                  │                  │           │
│           └──────────────────┼──────────────────┘           │
│                              │                              │
│                    ┌─────────▼─────────┐                    │
│                    │   GPG 签名验证    │                    │
│                    └─────────┬─────────┘                    │
│                              │                              │
│                    ┌─────────▼─────────┐                    │
│                    │   版本管理系统    │                    │
│                    │   (5.0/6.0/dev)   │                    │
│                    └─────────┬─────────┘                    │
│                              │                              │
│                    ┌─────────▼─────────┐                    │
│                    │   CI/CD 流水线    │                    │
│                    │   (GitHub Actions)│                    │
│                    └───────────────────┘                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 目录结构

```
opentenbase-repo/
├── .github/
│   └── workflows/
│       ├── build-deb.yml          # Debian/Ubuntu 构建
│       ├── build-rpm.yml          # RHEL/CentOS 构建
│       └── publish-repo.yml       # 发布到仓库
├── docker/
│   ├── ubuntu-20.04.Dockerfile    # Ubuntu 20.04 构建环境
│   ├── ubuntu-22.04.Dockerfile    # Ubuntu 22.04 构建环境
│   ├── ubuntu-24.04.Dockerfile    # Ubuntu 24.04 构建环境
│   ├── debian-11.Dockerfile       # Debian 11 构建环境
│   └── debian-12.Dockerfile       # Debian 12 构建环境
├── scripts/
│   ├── build-deb.sh               # 构建脚本
│   ├── sign-packages.sh           # 签名脚本
│   └── publish-repo.sh            # 发布脚本
├── repo/
│   ├── apt/                       # APT 仓库
│   │   ├── dists/
│   │   │   ├── focal/             # Ubuntu 20.04
│   │   │   ├── jammy/             # Ubuntu 22.04
│   │   │   ├── noble/             # Ubuntu 24.04
│   │   │   ├── bullseye/          # Debian 11
│   │   │   └── bookworm/          # Debian 12
│   │   └── pool/
│   │       └── main/
│   │           └── o/
│   │               └── opentenbase/
│   └── rpm/                       # RPM 仓库
│       ├── el8/                   # RHEL/CentOS 8
│       ├── el9/                   # RHEL/CentOS 9
│       └── fedora/                # Fedora
├── docs/
│   ├── installation.md            # 安装指南
│   ├── configuration.md           # 配置指南
│   └── troubleshooting.md         # 故障排查
└── README.md                      # 项目说明
```

---

## 实施路径

### 第 1 阶段：短期（1–2 周）——先把基础打牢

#### 目标
- 用 Docker 统一构建环境
- 构建 Ubuntu 20.04/22.04/24.04 + Debian 11/12 安装包
- 标准化 deb 打包规范

#### 任务清单

- [ ] **创建 Docker 构建环境**
  - [ ] Ubuntu 20.04 Dockerfile
  - [ ] Ubuntu 22.04 Dockerfile
  - [ ] Ubuntu 24.04 Dockerfile
  - [ ] Debian 11 Dockerfile
  - [ ] Debian 12 Dockerfile

- [ ] **更新 CI 工作流**
  - [ ] 修改 `.github/workflows/build.yml`
  - [ ] 添加 Docker 构建步骤
  - [ ] 测试所有版本构建

- [ ] **标准化打包规范**
  - [ ] 版本号规范（遵循 Debian 策略）
  - [ ] 依赖声明规范
  - [ ] 服务文件规范
  - [ ] 日志路径规范
  - [ ] 配置文件规范

- [ ] **测试验证**
  - [ ] Ubuntu 20.04 安装测试
  - [ ] Ubuntu 22.04 安装测试
  - [ ] Ubuntu 24.04 安装测试
  - [ ] Debian 11 安装测试
  - [ ] Debian 12 安装测试

#### 预期成果

- 5 个发行版的 .deb 包全部构建成功
- 所有包通过 lintian 检查
- 安装测试全部通过

---

### 第 2 阶段：中期（1–2 月）——建立官方级 APT 仓库

#### 目标
- 搭建带 GPG 签名的 APT 仓库
- 一键安装脚本
- 多版本管理

#### 任务清单

- [ ] **搭建 APT 仓库**
  - [ ] 安装和配置 `reprepro`
  - [ ] 创建仓库目录结构
  - [ ] 配置 GPG 签名
  - [ ] 测试仓库功能

- [ ] **创建一键安装脚本**
  - [ ] 检测系统版本
  - [ ] 添加 GPG 密钥
  - [ ] 配置仓库源
  - [ ] 安装软件包

- [ ] **多版本管理**
  - [ ] 设计版本命名规范
  - [ ] 支持多版本并存
  - [ ] 版本切换机制

- [ ] **文档完善**
  - [ ] 安装指南（中英文）
  - [ ] 配置指南
  - [ ] 故障排查指南

#### 预期成果

- APT 仓库正常运行
- 用户可通过一条命令安装
- 支持多版本并存

---

### 第 3 阶段：长期（3–6 月）——跨平台生态

#### 目标
- RPM 包支持（RHEL/CentOS/Rocky/Fedora）
- 自动 CI/CD 流水线
- 可直接合入 OpenTenBase 官方仓库

#### 任务清单

- [ ] **RPM 包支持**
  - [ ] 创建 RPM spec 文件
  - [ ] 构建 RHEL/CentOS 8 包
  - [ ] 构建 RHEL/CentOS 9 包
  - [ ] 构建 Fedora 包

- [ ] **自动 CI/CD 流水线**
  - [ ] 版本发布自动触发
  - [ ] 自动构建所有平台
  - [ ] 自动签名和发布
  - [ ] 自动更新仓库

- [ ] **官方贡献准备**
  - [ ] 代码质量审查
  - [ ] 文档完善
  - [ ] 测试覆盖率提升
  - [ ] 提交到 OpenTenBase 官方

#### 预期成果

- 支持 10+ 发行版
- 全自动 CI/CD 流水线
- 可直接贡献给官方

---

## 技术实现

### Docker 构建环境

#### Ubuntu 20.04 Dockerfile

```dockerfile
FROM ubuntu:20.04

# 设置非交互模式
ENV DEBIAN_FRONTEND=noninteractive

# 安装构建依赖
RUN apt-get update && apt-get install -y \
    build-essential \
    debhelper \
    devscripts \
    fakeroot \
    quilt \
    bison \
    flex \
    perl \
    libreadline-dev \
    zlib1g-dev \
    libssl-dev \
    libpam0g-dev \
    libxml2-dev \
    libldap2-dev \
    libossp-uuid-dev \
    uuid-dev \
    libcurl4-openssl-dev \
    liblz4-dev \
    libzstd-dev \
    libssh2-1-dev \
    libpqxx-dev \
    libcli11-dev \
    pkg-config \
    libtool \
    && rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /build

# 复制构建脚本
COPY scripts/build-deb.sh /build/
RUN chmod +x /build/build-deb.sh

# 默认执行构建
CMD ["/build/build-deb.sh"]
```

### CI 工作流

```yaml
# .github/workflows/build-multi.yml
name: Build Multi-Distro Packages

on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        include:
          - distro: ubuntu
            version: "20.04"
            codename: focal
          - distro: ubuntu
            version: "22.04"
            codename: jammy
          - distro: ubuntu
            version: "24.04"
            codename: noble
          - distro: debian
            version: "11"
            codename: bullseye
          - distro: debian
            version: "12"
            codename: bookworm

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build packages
        run: |
          docker build \
            --file docker/${{ matrix.distro }}-${{ matrix.version }}.Dockerfile \
            --tag opentenbase-builder:${{ matrix.distro }}-${{ matrix.version }} \
            .

          docker run \
            --volume $(pwd)/output:/output \
            opentenbase-builder:${{ matrix.distro }}-${{ matrix.version }}

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: debs-${{ matrix.distro }}-${{ matrix.codename }}
          path: output/*.deb

  publish:
    needs: build
    runs-on: ubuntu-latest
    if: startsWith(github.ref, 'refs/tags/')

    steps:
      - name: Download all artifacts
        uses: actions/download-artifact@v4
        with:
          path: all-debs

      - name: Sign and publish
        run: |
          # 签名和发布到仓库
          ./scripts/publish-repo.sh
```

### 一键安装脚本

```bash
#!/bin/bash
# OpenTenBase 一键安装脚本
# Usage: curl -sSL https://opentenbase.org/repo/setup.sh | sudo bash

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 root 权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "必须以 root 权限运行此脚本"
        exit 1
    fi
}

# 检测系统版本
detect_os() {
    if [ ! -f /etc/os-release ]; then
        log_error "无法检测操作系统版本"
        exit 1
    fi

    . /etc/os-release
    
    case "$ID" in
        ubuntu)
            OS="ubuntu"
            CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
            ;;
        debian)
            OS="debian"
            CODENAME="$VERSION_CODENAME"
            ;;
        *)
            log_error "不支持的操作系统: $ID"
            exit 1
            ;;
    esac

    log_info "检测到: $OS $VERSION_ID ($CODENAME)"
}

# 添加 GPG 密钥
add_gpg_key() {
    log_info "添加 GPG 密钥..."
    
    curl -fsSL https://opentenbase.org/repo/gpg-key.asc | \
        gpg --dearmor -o /usr/share/keyrings/opentenbase-archive-keyring.gpg
    
    chmod 644 /usr/share/keyrings/opentenbase-archive-keyring.gpg
}

# 配置仓库源
configure_repo() {
    log_info "配置仓库源..."
    
    echo "deb [signed-by=/usr/share/keyrings/opentenbase-archive-keyring.gpg] \
        https://opentenbase.org/repo/apt $CODENAME main" \
        > /etc/apt/sources.list.d/opentenbase.list
    
    chmod 644 /etc/apt/sources.list.d/opentenbase.list
}

# 安装 OpenTenBase
install_opentenbase() {
    log_info "更新软件包列表..."
    apt-get update -qq
    
    log_info "安装 OpenTenBase..."
    apt-get install -y opentenbase
    
    log_info "安装完成！"
    echo ""
    echo "快速开始:"
    echo "  opentenbase-ctl init    # 初始化集群"
    echo "  opentenbase-ctl start   # 启动所有节点"
    echo "  opentenbase-ctl status  # 检查状态"
    echo ""
    echo "连接数据库:"
    echo "  opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d postgres"
}

# 主函数
main() {
    echo "========================================"
    echo "  OpenTenBase 一键安装脚本"
    echo "========================================"
    echo ""
    
    check_root
    detect_os
    add_gpg_key
    configure_repo
    install_opentenbase
}

# 执行主函数
main "$@"
```

---

## 成功案例参考

### PostgreSQL 官方仓库

- **仓库地址**: https://apt.postgresql.org/
- **支持系统**: Ubuntu 20.04/22.04/24.04 + Debian 11/12
- **特点**: 
  - 每个版本独立的 `.deb` 包
  - 通过仓库自动选择
  - GPG 签名验证
  - 多版本并存

### Docker 官方仓库

- **仓库地址**: https://download.docker.com/
- **支持系统**: Ubuntu 20.04/22.04/24.04 + Debian 11/12 + CentOS/RHEL
- **特点**:
  - 统一的安装脚本
  - 自动检测系统版本
  - 一键安装

### NodeSource 仓库

- **仓库地址**: https://deb.nodesource.com/
- **支持系统**: Ubuntu 20.04/22.04/24.04 + Debian 11/12
- **特点**:
  - 一键安装脚本
  - 自动配置仓库
  - 多版本管理

---

## 维护策略

### 版本发布流程

1. **代码冻结**: 发布前 1 周冻结代码
2. **测试验证**: 全平台测试
3. **版本打 tag**: 使用语义化版本
4. **自动构建**: CI 自动触发构建
5. **签名发布**: 自动签名和发布
6. **更新仓库**: 自动更新 APT/RPM 仓库

### 安全更新策略

1. **安全漏洞响应**: 24 小时内发布修复
2. **自动通知**: 通过邮件列表通知用户
3. **版本回退**: 支持快速回退到稳定版本

### 文档更新策略

1. **同步更新**: 代码和文档同步更新
2. **多语言支持**: 中英文双语
3. **版本化文档**: 每个版本独立文档

---

## 总结

### 方案优势

- ✅ **长期稳定**: 可维护 5-10 年
- ✅ **全平台支持**: Debian/Ubuntu 全系列
- ✅ **官方标准**: 符合 Linux 发行版标准
- ✅ **用户友好**: 一键安装
- ✅ **自动维护**: CI/CD 自动化

### 对比其他方案

| 方案 | 支持版本 | 复杂度 | 用户体验 | 长期维护 | 推荐度 |
|------|----------|--------|----------|----------|--------|
| 扩展 CI 矩阵 | 3-4 个 | 低 | 中 | 差 | ⭐⭐ |
| Launchpad PPA | 仅 Ubuntu | 中 | 高 | 中 | ⭐⭐⭐ |
| Docker 容器 | 所有 | 中 | 中 | 中 | ⭐⭐⭐⭐ |
| **自建 APT 仓库** | **所有** | **高** | **最高** | **最好** | **⭐⭐⭐⭐⭐** |

### 最终建议

**推荐选择：自建 APT 仓库 + Docker 构建**

这是**开源项目官方打包的标准路线**，也是你能给 OpenTenBase 留下的**最有价值的长期贡献**。

---

**文档版本**: 1.0  
**最后更新**: 2026-05-20  
**维护者**: muzimu217
