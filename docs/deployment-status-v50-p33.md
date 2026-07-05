# OpenTenBase v5.0-p33 部署状态报告

**日期**: 2026-07-06
**版本**: v5.0-p33 (已修复端口分配bug)

## 双服务器部署状态

### 服务器A (162.14.74.145)
- **状态**: ✅ 正常运行
- **工具**: pgxc_ctl
- **进程数**: 31
- **端口监听**: 
  - GTM: 6666
  - Coordinator: 5432  
  - Datanode: 15432
- **数据库功能**: 正常（建表/读写测试通过）

### 服务器B (150.158.77.134)
- **状态**: ✅ 正常运行
- **工具**: pgxc_ctl
- **进程数**: 26
- **端口监听**:
  - GTM: 6666
  - Coordinator: 5432
  - Datanode: 15432
- **数据库功能**: 正常（建表/读写测试通过）

## 部署工具对比

| 工具 | 状态 | 备注 |
|------|------|------|
| pgxc_ctl | ✅ 正常 | 两个服务器均验证通过 |
| opentenbase_ctl | ⏳ 待验证 | 端口分配bug已修复，待CI完整编译后测试 |

## 端口分配bug修复

### Bug描述
`opentenbase_ctl` 使用 `START_PORT=11000` 导致端口溢出，产生负数端口：
```
CN/DN port = -1836016720 (invalid)
```

### 修复方案
修改为标准OpenTenBase端口：
```cpp
const int GTM_START_PORT = 6666;
const int CN_START_PORT = 5432;
const int DN_START_PORT = 15432;
```

### 修复提交
- **仓库**: muzimu217/OpenTenBase (个人fork)
- **Commit**: f257c28e
- **Patch**: 05-port-allocation-fix.patch (已推送至社区仓库)

## 当前方案

按照用户要求，**目前使用pgxc_ctl确保两个集群正常运行**，后续待CI编译完成后测试修复后的opentenbase_ctl。

### 验证测试
```sql
-- 服务器A
CREATE TABLE verify_test(id INT, msg TEXT);
INSERT INTO verify_test VALUES(1, 'ServerA pgxc_ctl OK');
SELECT * FROM verify_test;

-- 服务器B  
INSERT INTO verify_test VALUES(2, 'ServerB pgxc_ctl OK');
SELECT * FROM verify_test ORDER BY id;
```

结果：两台服务器均成功执行。

## 配置文件路径

- **pgxc_ctl.conf**: `/var/lib/opentenbase/pgxc_ctl/pgxc_ctl.conf`
- **GTM数据目录**: `/var/lib/opentenbase/5/gtm`
- **Coordinator数据目录**: `/var/lib/opentenbase/5/coord0001`
- **Datanode数据目录**: `/var/lib/opentenbase/5/dn0001`

## 日常运维命令

```bash
export PATH=/usr/lib/opentenbase/5.0/bin:$PATH
export LD_LIBRARY_PATH=/usr/lib/opentenbase/5.0/lib

pgxc_ctl monitor all   # 查看集群状态
pgxc_ctl start all     # 启动集群
pgxc_ctl stop all      # 停止集群

psql -h 127.0.0.1 -p 5432 -U opentenbase -d postgres
```

## 下一步计划

1. 等待CI编译完成完整RPM包（包含opentenbase_ctl二进制）
2. 在两台服务器上测试修复后的opentenbase_ctl
3. 验证两个CTL工具都能正常工作
4. 更新文档

---

**维护者**: Claude Code
**更新时间**: 2026-07-06 00:33 CST
