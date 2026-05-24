# OpenTenBase Multi-Version Management

[English](VERSION-MANAGEMENT.md) | [中文](VERSION-MANAGEMENT_zh.md)

## Overview

OpenTenBase supports installing multiple versions side-by-side, similar to how PostgreSQL manages `postgresql-14`, `postgresql-15`, etc. Each version installs to its own isolated directory tree and has its own configuration and data directories.

## Directory Structure

```
/usr/lib/opentenbase/
├── 5.0/                    # v5.0 binaries and libraries (latest)
│   ├── bin/
│   ├── lib/
│   └── share/
├── 2.6.0/                  # v2.6.0 binaries and libraries
│   ├── bin/
│   ├── lib/
│   └── share/
└── 2.5.0/                  # v2.5.0 binaries and libraries
    ├── bin/
    ├── lib/
    └── share/

/etc/opentenbase/
├── 5.0/                    # v5.0 configuration
│   ├── opentenbase.conf
│   ├── gtm.conf.template
│   └── ...
├── 2.6.0/                  # v2.6.0 configuration
└── current -> 5.0/         # Active version symlink

/var/lib/opentenbase/
├── 5.0/                    # v5.0 data
│   ├── gtm/
│   ├── coord/
│   └── dn1/
└── 2.6.0/                  # v2.6.0 data

/var/log/opentenbase/
├── 5.0/                    # v5.0 logs
│   ├── gtm.log
│   ├── coord.log
│   └── dn1.log
└── 2.6.0/                  # v2.6.0 logs
```

## Quick Start

### Install a Specific Version

```bash
# Install v5.0 (default, latest)
curl -sSL https://github.com/muzimu217/OpenTenBase-deb/releases/latest/download/install.sh | sudo bash

# Install a specific version
curl -sSL https://github.com/muzimu217/OpenTenBase-deb/releases/latest/download/install.sh | sudo bash -s -- --version 5.0
curl -sSL https://github.com/muzimu217/OpenTenBase-deb/releases/latest/download/install.sh | sudo bash -s -- --version 2.6.0
```

### List Installed Versions

```bash
opentenbase-switch-version
```

Output example:
```
Installed OpenTenBase versions:

  5.0 (active)
    prefix: /usr/lib/opentenbase/5.0
    coord port: 5432

[INFO] Active version: 5.0
```

### Switch Versions

```bash
# Switch to v5.0 (latest)
sudo opentenbase-switch-version 5.0

# Switch to v2.6.0
sudo opentenbase-switch-version 2.6.0
```

### Verify Current Version

```bash
# Check which version is active
readlink /etc/opentenbase/current

# Check binary version
/usr/lib/opentenbase/5.0/bin/postgres --version
```

## Running Multiple Versions Simultaneously

By default, each version uses the same ports (5432 for coordinator, 6666 for GTM, 15432 for datanode). To run multiple versions simultaneously, you need to use different ports.

### Method 1: Edit Configuration

```bash
# Stop current version
opentenbase-ctl stop

# Edit the config for the second version
sudo vi /etc/opentenbase/2.6.0/opentenbase.conf

# Change ports:
#   GTM_PORT=6667
#   COORD_PORT=5433
#   DN1_PORT=15433
#   COORD_FORWARD_PORT=6671
#   DN1_FORWARD_PORT=6672
#   COORD_POOLER_PORT=6669
#   DN1_POOLER_PORT=6670

# Initialize and start second version
sudo opentenbase-switch-version 2.6.0
opentenbase-ctl init
opentenbase-ctl start

# Start first version (needs to switch back)
sudo opentenbase-switch-version 5.0
opentenbase-ctl start
```

### Method 2: Environment Variable Override

```bash
# Use OTB_CONFIG to point to specific version config
OTB_CONFIG=/etc/opentenbase/5.0/opentenbase.conf opentenbase-ctl start
OTB_CONFIG=/etc/opentenbase/2.6.0/opentenbase.conf opentenbase-ctl start
```

## Version Management Commands

| Command | Description |
|---------|-------------|
| `opentenbase-switch-version` | List installed versions |
| `opentenbase-switch-version 5.0` | Switch to v5.0 |
| `opentenbase-switch-version 2.6.0` | Switch to v2.6.0 |
| `opentenbase-ctl init` | Initialize cluster (current version) |
| `opentenbase-ctl start` | Start cluster (current version) |
| `opentenbase-ctl stop` | Stop cluster (current version) |
| `opentenbase-ctl status` | Check status (current version) |

## Upgrading Between Versions

### In-Place Upgrade (Same Major Version)

```bash
# Stop the current version
opentenbase-ctl stop

# Install new package (will overwrite files in versioned directory)
sudo dpkg -i opentenbase_5.1-1ubuntu1_amd64.deb

# Start with updated binaries
opentenbase-ctl start
```

### Side-by-Side Upgrade (Different Major Version)

```bash
# Install new version alongside existing
sudo bash install.sh --version 2.6.0

# Switch to new version
sudo opentenbase-switch-version 2.6.0

# Initialize new version's data
opentenbase-ctl init

# Start new version
opentenbase-ctl start

# Old version remains at /var/lib/opentenbase/5.0/
```

## Troubleshooting

### "cannot read /etc/opentenbase/current/opentenbase.conf"

The current symlink is not set up. Fix it:

```bash
sudo ln -sf /etc/opentenbase/5.0 /etc/opentenbase/current
```

### Port Conflicts

If you see "port already in use" errors:

```bash
# Check what's using the port
ss -tlnp | grep 5432

# Either stop the conflicting process or change ports in the config
sudo vi /etc/opentenbase/<version>/opentenbase.conf
```

### Version Not Found

```bash
# List installed versions
opentenbase-switch-version

# Check if config directory exists
ls -la /etc/opentenbase/
```

## For Package Maintainers

### Adding a New Version

When building packages for a new OpenTenBase version (e.g., v6.0):

1. Update `OTB_VERSION` in `debian/rules` to `6.0`
2. Update `OTB_VERSION` in `debian/opentenbase-server.postinst` to `6.0`
3. Update version paths in `config/opentenbase.conf`
4. Update `Version` in `rpm/opentenbase.spec`
5. Adjust ports in `config/opentenbase.conf` if needed for parallel operation

### CI/CD Version Matrix

The build workflows support a `version` parameter:

```yaml
# In .github/workflows/build-deb.yml
workflow_dispatch:
  inputs:
    version:
      description: 'OpenTenBase version (e.g., 5.0, 6.0)'
      required: true
      default: '5.0'
```
