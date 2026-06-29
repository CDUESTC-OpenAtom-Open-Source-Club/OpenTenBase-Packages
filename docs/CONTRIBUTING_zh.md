# 贡献指南

[English](CONTRIBUTING.md) | 中文

感谢您对 OpenTenBase .deb 打包项目的关注！

## 如何贡献

### 报告问题

1. 访问 [Issues 页面](https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/issues)
2. 点击 "New Issue"
3. 提供详细信息：
   - **Ubuntu 版本**：例如 Ubuntu 22.04、24.04
   - **错误信息**：复制完整的错误输出
   - **复现步骤**：触发问题的详细步骤
   - **预期行为**：您期望发生什么
   - **实际行为**：实际发生了什么

### 提交代码

1. **Fork 仓库**
   ```bash
   # 在 GitHub 上点击 "Fork" 按钮
   ```

2. **克隆您的 fork**
   ```bash
   git clone https://github.com/YOUR_USERNAME/OpenTenBase-Packages.git
   cd OpenTenBase-Packages
   ```

3. **创建特性分支**
   ```bash
   git checkout -b feature/your-feature-name
   ```

4. **进行修改**
   - 遵循现有代码风格
   - 为复杂逻辑添加注释
   - 彻底测试您的更改

5. **提交更改**
   ```bash
   git add .
   git commit -m "feat: 添加您的特性描述"
   ```

6. **推送到您的 fork**
   ```bash
   git push origin feature/your-feature-name
   ```

7. **创建 Pull Request**
   - 前往原始仓库
   - 点击 "New Pull Request"
   - 选择您的分支
   - 提供清晰的更改描述

### 开发环境设置

#### 前提条件

- Ubuntu 22.04 或 24.04
- Git
- 构建依赖（见下文）

#### 安装构建依赖

```bash
sudo apt update
sudo apt install -y debhelper-compat bison flex perl gcc g++ make \
    libreadline-dev zlib1g-dev libssl-dev libpam0g-dev \
    libxml2-dev libldap2-dev libossp-uuid-dev uuid-dev \
    libcurl4-openssl-dev liblz4-dev libzstd-dev \
    libcli11-dev libpqxx-dev quilt libtool pkg-config
```

#### 构建软件包

```bash
# 克隆 OpenTenBase 源码
git clone https://github.com/OpenTenBase/OpenTenBase.git
cd OpenTenBase

# 复制打包文件
cp -r /path/to/OpenTenBase-Packages/* ./

# 构建软件包
fakeroot debian/rules binary
```

### 代码风格

- **Shell 脚本**：遵循 [Google Shell 风格指南](https://google.github.io/styleguide/shellguide.html)
- **Debian 打包**：遵循 [Debian 策略手册](https://www.debian.org/doc/debian-policy/)
- **提交信息**：使用 [约定式提交](https://www.conventionalcommits.org/)

### 测试

在提交 Pull Request 之前：

1. **构建测试**
   ```bash
   fakeroot debian/rules binary
   ```

2. **Lintian 检查**
   ```bash
   lintian *.deb
   ```

3. **安装测试**
   ```bash
   sudo apt install ./*.deb
   ```

4. **功能测试**
   ```bash
   # 准备 INI 配置文件（模板：/etc/opentenbase/5.0/opentenbase_config.ini.example）
   opentenbase_ctl install -c /tmp/otb_config.ini
   opentenbase_ctl start
   opentenbase_ctl status
   ```

## 贡献类型

### Bug 修复

- 修复构建问题
- 修复安装问题
- 修复运行时错误
- 修复文档错误

### 功能增强

- 添加对新 Ubuntu 版本的支持
- 改进安装脚本
- 添加配置选项
- 增强文档

### 文档改进

- 改进 README 文件
- 添加示例
- 修复拼写错误
- 翻译文档

### 测试

- 添加测试用例
- 改进测试覆盖率
- 添加 CI/CD 改进

## 行为准则

请在所有互动中保持尊重和包容。

## 有问题？

如果您对贡献有疑问：

1. 检查现有的 [Issues](https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/issues)
2. 创建新 issue 提出您的问题
3. 在现有 issue 中参与讨论

## 许可证

通过贡献，您同意您的贡献将在与项目相同的许可证（Apache 2.0）下获得许可。

---

**感谢您的贡献！**
