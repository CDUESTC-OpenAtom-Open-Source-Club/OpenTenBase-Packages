# OpenTenBase 源码编译部署指南

> 本指南介绍如何从源码编译并部署 OpenTenBase 集群，支持二次开发。

---

## 1. 适用场景

- **二次开发**：修改 OpenTenBase 源码并测试
- **性能调优**：自定义编译选项优化性能
- **学习研究**：理解 OpenTenBase 内部机制
- **定制功能**：添加自定义功能或插件

---

## 2. 前置要求

### 2.1 系统要求

- **操作系统**：Linux / macOS / Windows (with WSL2)
- **Docker**：20.10+
- **Docker Compose**：2.0+
- **内存**：至少 8GB（推荐 16GB）
- **磁盘**：至少 20GB 可用空间
- **网络**：需要访问 GitHub（下载源码）

### 2.2 安装 Docker

```bash
# Linux (Ubuntu/Debian)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# macOS
brew install --cask docker

# 启动 Docker Desktop
```

---

## 3. 快速开始

### 3.1 克隆仓库

```bash
# 克隆 OpenTenBase 源码仓库
git clone https://github.com/Tencent/OpenTenBase.git opentenbase-source

# 或者克隆你的 fork
git clone https://github.com/YOUR_USERNAME/OpenTenBase.git opentenbase-source
```

### 3.2 编译并启动集群

```bash
# 进入集群目录
cd OpenTenBase-Packages/docker/cluster

# 设置源码目录路径
export OPENTENBASE_SOURCE=/path/to/opentenbase-source

# 构建 Docker 镜像（包含编译环境）
docker compose -f docker-compose.source.yml build builder

# 启动编译容器
docker compose -f docker-compose.source.yml up -d builder

# 进入编译容器
docker exec -it opentenbase-builder bash

# 在容器内执行编译
/data/opentenbase/build-source.sh /data/opentenbase/source
```

**编译时间**：约 30-60 分钟（取决于 CPU 性能）

### 3.3 启动集群

```bash
# 编译完成后，启动集群
docker compose -f docker-compose.source.yml up -d

# 查看集群状态
docker compose -f docker-compose.source.yml ps
```

预期输出：
```
NAME                    STATUS          PORTS
opentenbase-gtm-source  Up 30 seconds   0.0.0.0:6666->6666/tcp
opentenbase-cn-source   Up 25 seconds   0.0.0.0:15432->15432/tcp
opentenbase-dn1-source  Up 20 seconds   0.0.0.0:15433->15432/tcp
opentenbase-dn2-source  Up 20 seconds   0.0.0.0:15434->15432/tcp
```

---

## 4. 二次开发流程

### 4.1 修改源码

```bash
# 在宿主机上修改源码
cd /path/to/opentenbase-source

# 使用你喜欢的编辑器
vim src/backend/executor/nodeModifyTable.c

# 或者使用 VS Code
code .
```

### 4.2 重新编译

```bash
# 进入编译容器
docker exec -it opentenbase-builder bash

# 清理之前的编译
cd /data/opentenbase/source
make clean

# 重新编译
make -j$(nproc)

# 重新安装
make install

# 验证
ls -lh /data/opentenbase/install/bin/postgres
```

### 4.3 重启集群

```bash
# 停止集群
docker compose -f docker-compose.source.yml down

# 启动集群
docker compose -f docker-compose.source.yml up -d
```

### 4.4 测试修改

```bash
# 连接到集群
psql -h localhost -p 15432 -U opentenbase -d opentenbase

# 执行测试查询
SELECT * FROM pgxc_node;
```

---

## 5. 高级功能

### 5.1 自定义编译选项

编辑编译脚本中的 `configure_build()` 函数：

```bash
# docker/cluster/scripts/build-source.sh

configure_build() {
    cd "$SOURCE_DIR"
    
    ./configure \
        --prefix="$INSTALL_DIR" \
        --enable-debug \              # 启用调试信息
        --enable-cassert \            # 启用断言检查
        --enable-depend \             # 启用依赖跟踪
        --with-openssl \              # 支持 SSL
        --with-pam \                  # 支持 PAM 认证
        --with-ldap \                 # 支持 LDAP
        --with-libxml \               # 支持 XML
        --with-libcurl \              # 支持 libcurl
        --with-lz4 \                  # 支持 lz4 压缩
        --with-zstd \                 # 支持 zstd 压缩
        --with-uuid=e2fs \            # UUID 支持
        CFLAGS="-O2 -g" \             # 编译优化选项
        --enable-thread-safety        # 线程安全
}
```

### 5.2 调试模式

```bash
# 使用 GDB 调试
docker exec -it opentenbase-cn-source bash

# 启动带调试信息的进程
gdb --args /data/opentenbase/install/bin/postgres -D /data/opentenbase/data/coordinator -Z coordinator

# GDB 常用命令
(gdb) break main           # 设置断点
(gdb) run                  # 运行
(gdb) next                 # 单步执行
(gdb) print variable_name  # 打印变量
(gdb) continue             # 继续执行
```

### 5.3 性能分析

```bash
# 使用 perf 进行性能分析
docker exec -it opentenbase-cn-source bash

# 记录性能数据
perf record -g -p $(pgrep postgres)

# 分析报告
perf report

# 火焰图
perf script | stackcollapse-perf.pl | flamegraph.pl > flamegraph.svg
```

---

## 6. 常见问题

### 6.1 编译失败

**问题**：编译过程中出现错误

**解决方案**：

```bash
# 检查依赖
docker exec -it opentenbase-builder bash
rpm -qa | grep -E "gcc|make|bison|flex"

# 手动安装缺失的依赖
dnf install -y <缺失的包>

# 清理并重新编译
cd /data/opentenbase/source
make clean
./configure --prefix=/data/opentenbase/install
make -j$(nproc)
make install
```

### 6.2 编译时间过长

**问题**：编译超过 60 分钟

**解决方案**：

```bash
# 增加并发编译
docker compose -f docker-compose.source.yml build --build-arg BUILDKIT_INLINE_CACHE=1 builder

# 或者在宿主机上编译（更快）
# 1. 在宿主机上安装依赖
# 2. 直接编译源码
# 3. 将编译产物挂载到容器
```

### 6.3 内存不足

**问题**：编译时 OOM（Out of Memory）

**解决方案**：

```bash
# 增加 Docker 内存限制
# Docker Desktop -> Settings -> Resources -> Memory: 8GB+

# 或者减少并发数
cd /data/opentenbase/source
make -j2  # 只使用 2 个核心
```

### 6.4 集群无法启动

**问题**：容器启动失败

**解决方案**：

```bash
# 查看日志
docker compose -f docker-compose.source.yml logs gtm
docker compose -f docker-compose.source.yml logs cn

# 检查编译产物
docker exec -it opentenbase-builder ls -lh /data/opentenbase/install/bin/

# 重新初始化
docker compose -f docker-compose.source.yml down -v
docker compose -f docker-compose.source.yml up -d
```

---

## 7. 性能对比

| 方式 | 编译时间 | 启动时间 | 适用场景 |
|------|---------|---------|---------|
| 预编译二进制 | 无 | ~2 分钟 | 快速部署、生产环境 |
| 源码编译 | 30-60 分钟 | ~2 分钟 | 二次开发、学习研究 |
| 增量编译 | 5-10 分钟 | ~2 分钟 | 修改代码后快速测试 |

---

## 8. 最佳实践

### 8.1 开发流程

```bash
# 1. 克隆源码
git clone https://github.com/Tencent/OpenTenBase.git opentenbase-source

# 2. 创建开发分支
cd opentenbase-source
git checkout -b feature/my-feature

# 3. 首次完整编译
docker compose -f docker-compose.source.yml build builder
docker compose -f docker-compose.source.yml up -d builder
docker exec -it opentenbase-builder bash -c "/data/opentenbase/build-source.sh /data/opentenbase/source"

# 4. 修改代码
vim src/backend/.../xxx.c

# 5. 增量编译
docker exec -it opentenbase-builder bash
cd /data/opentenbase/source
make -j$(nproc)
make install

# 6. 重启集群测试
docker compose -f docker-compose.source.yml restart cn dn1 dn2

# 7. 提交代码
git add .
git commit -m "Add my feature"
git push origin feature/my-feature
```

### 8.2 优化编译速度

```bash
# 使用 ccache 加速编译
dnf install -y ccache

# 设置环境变量
export CC="gcc"
export CXX="g++"
export USE_CCACHE=1

# 编译时会自动缓存
make -j$(nproc)
```

### 8.3 版本管理

```bash
# 记录编译的 Git 版本
cd /data/opentenbase/source
git log -1 --format="%H" > /data/opentenbase/install/GIT_COMMIT

# 查看编译版本
cat /data/opentenbase/install/GIT_COMMIT
```

---

## 9. 与预编译方式对比

| 特性 | 预编译方式 | 源码编译方式 |
|------|-----------|-------------|
| 部署速度 | 快 | 慢（首次编译） |
| 二次开发 | 不支持 | 支持 |
| 自定义选项 | 不支持 | 支持 |
| 调试信息 | 无 | 可选 |
| 适用场景 | 生产环境 | 开发环境 |
| 镜像大小 | 小 | 大（包含编译环境） |

---

## 10. 总结

通过源码编译方式部署 OpenTenBase 集群，开发者可以：

✅ 修改源码并快速测试  
✅ 自定义编译选项优化性能  
✅ 使用调试工具分析问题  
✅ 学习和研究 OpenTenBase 内部机制  
✅ 贡献代码到开源社区  

**关键优势**：
- 完整的二次开发支持
- 灵活的编译选项
- 持久化的编译环境
- 快速的增量编译

**推荐场景**：
- 学习和教学
- 二次开发和定制
- 性能优化研究
- 贡献开源项目

---

## 11. 延伸阅读

- [OpenTenBase 官方文档](https://docs.opentenbase.org)
- [01-quickstart.md](./tutorials/01-quickstart.md)：快速入门
- [03-architecture.md](./tutorials/03-architecture.md)：架构详解
- [04-advanced.md](./tutorials/04-advanced.md)：高级功能

---

**作者：** OpenTenBase 社区  
**更新时间：** 2024-05  
**版本：** 1.0