# Static Binaries for OpenTenBase Deployment

This directory contains statically-linked binaries required for OpenTenBase cluster deployment
in environments where package managers are unavailable or restricted.

## Available Binaries

| Binary | Architecture | Purpose |
|--------|--------------|---------|
| `sshpass-x86_64` | x86_64 (amd64) | Non-interactive SSH password authentication |
| `sshpass-aarch64` | aarch64 (ARM64) | Non-interactive SSH password authentication |

## Why Static Binaries?

OpenTenBase cluster management tools (`opentenbase_ctl` and `pgxc_ctl`) use `sshpass` internally
for remote SSH operations during cluster deployment. In some environments:

- **Restricted containers**: No package manager access
- **Minimal systems**: Alpine, stripped-down OS images
- **EulerOS/openEuler**: `sshpass` not available in official repos
- **No root access**: Cannot install packages

Static binaries provide a **universal fallback** that works across all these scenarios.

## Build Instructions

### sshpass (from source)

```bash
# Download source
curl -fsSL https://sourceforge.net/projects/sshpass/files/sshpass/1.10/sshpass-1.10.tar.gz/download -o sshpass-1.10.tar.gz
tar -xzf sshpass-1.10.tar.gz
cd sshpass-1.10

# Configure for static linking
./configure --prefix=/usr/local LDFLAGS="-static"

# Build
make

# Verify it's static
file sshpass | grep -q "statically linked" && echo "OK: static binary" || echo "WARN: dynamic binary"

# Strip for smaller size
strip sshpass

# Rename by architecture
mv sshpass sshpass-$(uname -m)
```

### Cross-compilation

For cross-architecture builds (e.g., building aarch64 on x86_64):

```bash
# Install cross-compiler
apt-get install gcc-aarch64-linux-gnu  # Debian/Ubuntu
# or
dnf install gcc-aarch64-linux-gnu       # RHEL/Fedora

# Configure with cross-compiler
./configure --host=aarch64-linux-gnu CC=aarch64-linux-gnu-gcc LDFLAGS="-static"
make
```

## Verification

After download, verify the binary:

```bash
# Check architecture matches
file sshpass-$(uname -m) | grep "$(uname -m)"

# Test execution
sshpass-$(uname -m) -V

# Verify static linking (no external dependencies)
ldd sshpass-$(uname -m) || echo "Static binary (no ldd output expected)"
```

## CDN Hosting

These binaries are hosted at:
- Primary: `https://repo.blackevil217.com/binaries/sshpass-{arch}`
- Fallback: `https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/binaries/sshpass-{arch}`

## Security Note

- Static binaries are built from official source releases
- No modifications to the source code
- Binaries are stripped but not obfuscated
- Use for deployment convenience, not as a permanent system replacement

## Adding New Binaries

When adding new static binaries:

1. Build from official source (no patches)
2. Verify static linking with `ldd` or `file`
3. Strip to reduce size: `strip binary`
4. Name by architecture: `binary-{arch}`
5. Add to this directory and update CDN
6. Update `binaries/README.md` with build instructions