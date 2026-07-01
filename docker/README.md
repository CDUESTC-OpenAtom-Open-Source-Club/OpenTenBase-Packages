# OpenTenBase Docker Compose

快速部署 OpenTenBase 分布式数据库集群。

## 快速开始

```bash
# 克隆仓库
git clone https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages.git
cd OpenTenBase-Packages/docker

# 启动集群
docker compose up -d

# 查看状态
docker compose ps

# 连接测试
docker compose exec coordinator psql -h localhost -p 5432 -U opentenbase -d postgres
```

## 服务架构

| 服务 | 容器名 | 端口 | 说明 |
|------|--------|------|------|
| gtm | opentenbase-gtm | 6666 | 全局事务管理器 |
| coordinator | opentenbase-coordinator | 5432 | 协调节点（SQL 入口） |
| datanode | opentenbase-datanode | 15432 | 数据节点 |

## 常用操作

```bash
# 启动集群
docker compose up -d

# 停止集群
docker compose down

# 停止并清理数据
docker compose down -v

# 查看日志
docker compose logs -f gtm

# 进入容器
docker compose exec coordinator bash

# 执行 SQL
docker compose exec coordinator psql -c "SELECT version();"
```

## 初始化集群

集群启动后，需要初始化分布式配置：

```bash
# 连接到 Coordinator
docker compose exec coordinator psql -h localhost -p 5432 -U opentenbase -d postgres

# 创建节点组
CREATE NODE GROUP default_group WITH (dn1);

# 创建分片映射
CREATE SHARDING GROUP default_group USING TABLESPACE default;

# 创建分布式表
CREATE TABLE test_table (id INT, name VARCHAR(100)) DISTRIBUTE BY SHARDING(id);
```

## 自定义配置

修改 `docker-compose.yml` 自定义：

```yaml
# 增加更多 Datanode
datanode2:
  image: opentenbase:5.0
  container_name: opentenbase-datanode2
  command: postgres --datanode -D /data/dn2 -i -p 15433
  ports:
    - "15433:15433"
```

## 生产环境建议

1. **持久化存储**：使用外部 volume 或 NFS
2. **高可用**：部署 GTM Proxy 和多副本
3. **监控**：集成 Prometheus + Grafana
4. **备份**：定期备份 `/data` 目录

## 故障排查

```bash
# 检查容器状态
docker compose ps

# 检查日志
docker compose logs --tail=100 coordinator

# 检查进程
docker compose exec coordinator ps aux | grep postgres

# 检查网络
docker compose exec coordinator ping gtm
```