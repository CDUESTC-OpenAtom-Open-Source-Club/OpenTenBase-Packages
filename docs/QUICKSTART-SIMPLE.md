# OpenTenBase 快速安装指南

## 一键安装（推荐）

只需一条命令即可完成安装：

```bash
curl -sSL https://get.opentenbase.com | sudo bash
```

安装完成后，执行两条命令即可运行：

```bash
opentenbase init    # 初始化集群
opentenbase start   # 启动服务
```

就这么简单！

---

## 安装后操作

### 启动服务
```bash
opentenbase start
```

### 查看状态
```bash
opentenbase status
```

### 连接数据库
```bash
opentenbase sql
```

### 停止服务
```bash
opentenbase stop
```

---

## 验证安装

启动后执行：

```bash
opentenbase sql
```

然后在 SQL 命令行中输入：

```sql
SELECT version();
```

看到 PostgreSQL 版本信息即表示安装成功！

---

## 支持的系统

| 系统 | 版本 |
|-----|-----|
| Ubuntu | 20.04, 22.04, 24.04 |
| Debian | 11, 12, 13 |
| Rocky Linux | 8, 9 |
| AlmaLinux | 8, 9 |
| openEuler | 22.03 |

---

## 手动安装（可选）

如果你更喜欢手动控制，也可以分步安装：

### Ubuntu/Debian
```bash
# 1. 配置软件源
curl -sSL https://repo.blackevil217.com/apt/gpg-key.asc | sudo gpg --dearmor -o /usr/share/keyrings/opentenbase.gpg
echo "deb [signed-by=/usr/share/keyrings/opentenbase.gpg] https://repo.blackevil217.com/apt noble main" | sudo tee /etc/apt/sources.list.d/opentenbase.list

# 2. 安装
sudo apt update && sudo apt install -y opentenbase
```

### Rocky/Alma/CentOS
```bash
# 1. 配置软件源
sudo rpm --import https://repo.blackevil217.com/rpm/gpg-key.asc
echo '[opentenbase]
name=OpenTenBase
baseurl=https://repo.blackevil217.com/rpm/el9/$basearch
enabled=1
gpgcheck=1' | sudo tee /etc/yum.repos.d/opentenbase.repo

# 2. 安装
sudo dnf install -y opentenbase
```

---

## 常见问题

### Q: 安装后怎么用？
A: 只需要两条命令：
```bash
opentenbase init   # 初始化
opentenbase start  # 启动
```

### Q: 如何切换版本？
A: 安装其他版本：
```bash
sudo apt install opentenbase-2.6   # 安装 v2.6.0
sudo apt install opentenbase-2.5   # 安装 v2.5.0
```

### Q: 集群配置在哪？
A: 配置文件位于 `/etc/opentenbase/5.0/opentenbase.ini`

### Q: 数据文件在哪？
A: 数据位于 `/var/lib/opentenbase/5.0/`

---

## 更多信息

- 完整文档: https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages
- 问题反馈: https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/issues