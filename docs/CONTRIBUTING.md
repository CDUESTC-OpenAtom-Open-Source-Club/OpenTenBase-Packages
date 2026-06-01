# Contributing to OpenTenBase .deb Packaging

English | [中文](CONTRIBUTING_zh.md)

Thank you for your interest in contributing to OpenTenBase .deb packaging!

## How to Contribute

### Reporting Issues

1. Visit the [Issues page](https://github.com/muzimu217/OpenTenBase-Packages/issues)
2. Click "New Issue"
3. Provide detailed information:
   - **Ubuntu version**: e.g., Ubuntu 22.04, 24.04
   - **Error messages**: Copy the full error output
   - **Steps to reproduce**: Detailed steps to trigger the issue
   - **Expected behavior**: What you expected to happen
   - **Actual behavior**: What actually happened

### Submitting Code

1. **Fork the repository**
   ```bash
   # Click "Fork" button on GitHub
   ```

2. **Clone your fork**
   ```bash
   git clone https://github.com/YOUR_USERNAME/OpenTenBase-Packages.git
   cd OpenTenBase-Packages
   ```

3. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

4. **Make your changes**
   - Follow the existing code style
   - Add comments for complex logic
   - Test your changes thoroughly

5. **Commit your changes**
   ```bash
   git add .
   git commit -m "feat: add your feature description"
   ```

6. **Push to your fork**
   ```bash
   git push origin feature/your-feature-name
   ```

7. **Create a Pull Request**
   - Go to the original repository
   - Click "New Pull Request"
   - Select your branch
   - Provide a clear description of your changes

### Development Setup

#### Prerequisites

- Ubuntu 22.04 or 24.04
- Git
- Build dependencies (see below)

#### Install Build Dependencies

```bash
sudo apt update
sudo apt install -y debhelper-compat bison flex perl gcc g++ make \
    libreadline-dev zlib1g-dev libssl-dev libpam0g-dev \
    libxml2-dev libldap2-dev libossp-uuid-dev uuid-dev \
    libcurl4-openssl-dev liblz4-dev libzstd-dev \
    libcli11-dev libpqxx-dev quilt libtool pkg-config
```

#### Build Packages

```bash
# Clone OpenTenBase source
git clone https://github.com/OpenTenBase/OpenTenBase.git
cd OpenTenBase

# Copy packaging files
cp -r /path/to/OpenTenBase-Packages/* ./

# Build packages
fakeroot debian/rules binary
```

### Code Style

- **Shell scripts**: Follow [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- **Debian packaging**: Follow [Debian Policy Manual](https://www.debian.org/doc/debian-policy/)
- **Commit messages**: Use [Conventional Commits](https://www.conventionalcommits.org/)

### Testing

Before submitting a pull request:

1. **Build test**
   ```bash
   fakeroot debian/rules binary
   ```

2. **Lintian check**
   ```bash
   lintian *.deb
   ```

3. **Installation test**
   ```bash
   sudo apt install ./*.deb
   ```

4. **Functionality test**
   ```bash
   opentenbase-ctl init
   opentenbase-ctl start
   opentenbase-ctl status
   ```

## Types of Contributions

### Bug Fixes

- Fix build issues
- Fix installation problems
- Fix runtime errors
- Fix documentation errors

### Features

- Add support for new Ubuntu versions
- Improve installation scripts
- Add configuration options
- Enhance documentation

### Documentation

- Improve README files
- Add examples
- Fix typos
- Translate documentation

### Testing

- Add test cases
- Improve test coverage
- Add CI/CD improvements

## Code of Conduct

Please be respectful and inclusive in all interactions.

## Questions?

If you have questions about contributing:

1. Check existing [Issues](https://github.com/muzimu217/OpenTenBase-Packages/issues)
2. Create a new issue with your question
3. Join the discussion in existing issues

## License

By contributing, you agree that your contributions will be licensed under the same license as the project (Apache 2.0).

---

**Thank you for contributing!**
