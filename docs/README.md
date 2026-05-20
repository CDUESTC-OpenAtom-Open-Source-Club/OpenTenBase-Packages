# OpenTenBase .deb Packaging

English | [中文](README_zh.md)

Ubuntu .deb packaging for [OpenTenBase](https://github.com/OpenTenBase/OpenTenBase) v5.0 (distributed SQL database based on PostgreSQL 10).

## Quick Install

### One-line Install (Recommended)

```bash
# Download and run installer
curl -sLO https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi8/install.sh
sudo bash install.sh
```

The installer automatically:
- Detects Ubuntu version (22.04 or 24.04)
- Downloads correct .deb packages
- Resolves dependencies via apt

### Manual Install

```bash
# For Ubuntu 24.04 (Noble)
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi8/opentenbase_5.0-1ubuntu1.noble_all.deb
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi8/opentenbase-server_5.0-1ubuntu1.noble_amd64.deb
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi8/opentenbase-client_5.0-1ubuntu1.noble_amd64.deb
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi8/opentenbase-contrib_5.0-1ubuntu1.noble_amd64.deb
sudo apt install ./*.deb
```

## Packages

| Package | Description |
|---------|-------------|
| `opentenbase` | Metapackage (depends on server + client) |
| `opentenbase-server` | Server binaries (postgres, gtm, pg_ctl) + service driver |
| `opentenbase-client` | Client utilities (psql, pg_dump) |
| `opentenbase-contrib` | Contributed extensions (pgbench, oid2name, etc.) |
| `libopentenbase-dev` | Development headers + pg_config |
| `opentenbase-doc` | SGML documentation sources |

## Quick Start

### Initialize Cluster

```bash
# Initialize GTM + Coordinator + Datanode
opentenbase-ctl init
```

### Start Cluster

```bash
# Start all nodes
opentenbase-ctl start
```

### Check Status

```bash
# Check cluster status
opentenbase-ctl status
```

### Connect to Database

```bash
# Connect via psql
opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d postgres
```

### Stop Cluster

```bash
# Stop all nodes
opentenbase-ctl stop
```

## Architecture

### Installation Paths

- **Main directory**: `/usr/lib/opentenbase/` (isolated from system PostgreSQL)
- **Config directory**: `/etc/opentenbase/`
- **Data directory**: `/var/lib/opentenbase/`
- **Log directory**: `/var/log/opentenbase/`
- **Management script**: `/usr/bin/opentenbase-ctl`

### Port Layout

| Service | Port | Description |
|---------|------|-------------|
| GTM | 6666 | Global Transaction Manager |
| Coordinator | 5432 | Coordinator node (external) |
| Datanode | 15432 | Data node |
| Coordinator Pooler | 6667 | Connection pool |
| Datanode Pooler | 6668 | Connection pool |
| Coordinator Forward | 6669 | Forward port |
| Datanode Forward | 6670 | Forward port |

### Startup Order

```
opentenbase-ctl start
    ├── 1. start_gtm()           # Start GTM
    ├── 2. start_coord()         # Start Coordinator
    ├── 3. register_nodes()      # Register nodes to pgxc_node
    │   ├── CREATE GTM NODE ...
    │   ├── CREATE NODE coord1 ...
    │   ├── CREATE NODE dn001 ...
    │   ├── pgxc_pool_reload()
    │   └── EXECUTE DIRECT ON (dn001) 'CREATE GTM NODE ...'
    ├── 4. start_dn1()           # Start Datanode
    └── 5. register_nodes()      # Final registration (ensure propagation)
```

## Build from Source

### Install Build Dependencies

```bash
apt install -y debhelper-compat bison flex perl gcc g++ make \
    libreadline-dev zlib1g-dev libssl-dev libpam0g-dev \
    libxml2-dev libldap2-dev libossp-uuid-dev uuid-dev \
    libcurl4-openssl-dev liblz4-dev libzstd-dev \
    libcli11-dev libpqxx-dev quilt libtool pkg-config
```

### Clone Source

```bash
git clone https://github.com/OpenTenBase/OpenTenBase.git
cd OpenTenBase
```

### Copy Packaging Files

```bash
cp -r /path/to/debian/ ./
```

### Build Packages

```bash
# Full compile
fakeroot debian/rules binary

# Or rebuild only .deb packages (no recompile)
fakeroot debian/rules binary
```

## Known Limitations

1. **License Issue**: OpenTenBase requires a valid license for write operations. Open-source version is read-only.
2. **Single-machine Deployment**: Current configuration only supports single-machine multi-node. Cross-machine deployment requires modifying `opentenbase.conf`.
3. **No systemd**: Some container environments don't have systemd, use `opentenbase-ctl` directly.
4. **Ubuntu 20.04 Support**: Focal packages not available due to GitHub Actions runner unavailability.

## Troubleshooting

### Common Issues

#### 1. Installation Failed: Dependency Issues

```bash
# Update package list
sudo apt update

# Fix dependencies
sudo apt install -f
```

#### 2. Cannot Connect to Database

```bash
# Check cluster status
opentenbase-ctl status

# View logs
tail -f /var/log/opentenbase/coord.log
```

#### 3. GTM Startup Failed

```bash
# Check GTM logs
tail -f /var/log/opentenbase/gtm.log

# Reinitialize cluster
opentenbase-ctl stop
opentenbase-ctl init
opentenbase-ctl start
```

#### 4. Port Conflict

```bash
# Check port usage
sudo netstat -tlnp | grep -E '(5432|6666|15432)'

# Stop conflicting services
sudo systemctl stop postgresql
```

## Contributing

Welcome to contribute code, report issues, or suggest improvements!

### Report Issues

1. Visit [Issues](https://github.com/muzimu217/OpenTenBase-deb/issues)
2. Click "New Issue"
3. Describe the issue in detail, including:
   - Ubuntu version
   - Error messages
   - Steps to reproduce

### Submit Code

1. Fork this repository
2. Create feature branch: `git checkout -b feature/your-feature`
3. Commit changes: `git commit -m 'Add your feature'`
4. Push branch: `git push origin feature/your-feature`
5. Create Pull Request

## License

Same as OpenTenBase (Apache 2.0).

## Related Links

- **GitHub Repository**: https://github.com/muzimu217/OpenTenBase-deb
- **Upstream Repository**: https://github.com/OpenTenBase/OpenTenBase
- **OpenTenBase Documentation**: https://github.com/OpenTenBase/OpenTenBase/wiki

---

**Maintainer**: muzimu217  
**Last Updated**: 2026-05-20

## Building from Source with Docker

### Prerequisites

- Docker installed and running
- Git

### Quick Start

```bash
# Clone the repository
git clone https://github.com/muzimu217/OpenTenBase-deb.git
cd opentenbase-deb

# Test build for Ubuntu 20.04
./test-build.sh -d ubuntu -v 20.04

# Test build for Debian 12
./test-build.sh -d debian -v 12

# Test all supported distributions
./test-build.sh --all
```

### Supported Build Environments

| Distribution | Version | Codename | Dockerfile |
|--------------|---------|----------|------------|
| Ubuntu | 20.04 | focal | docker-ubuntu-20.04.Dockerfile |
| Ubuntu | 22.04 | jammy | ubuntu-22.04.Dockerfile |
| Ubuntu | 24.04 | noble | ubuntu-24.04.Dockerfile |
| Debian | 11 | bullseye | docker-debian-11.Dockerfile |
| Debian | 12 | bookworm | docker-debian-12.Dockerfile |

### Manual Build

```bash
# Build Docker image for Ubuntu 20.04
docker build -f docker-ubuntu-20.04.Dockerfile -t opentenbase-builder:focal .

# Clone OpenTenBase source
git clone --depth=1 https://github.com/OpenTenBase/OpenTenBase.git source

# Run build
docker run \
    --rm \
    -v $(pwd)/source:/source \
    -v $(pwd)/output:/output \
    opentenbase-builder:focal

# Check output
ls -lh output/*.deb
```

### CI/CD Pipeline

The project uses GitHub Actions for automated builds:

- **build.yml**: Original workflow (Ubuntu 22.04/24.04)
- **build-multi.yml**: Multi-distro workflow (Ubuntu 20.04/22.04/24.04 + Debian 11/12)
- **build-multi-optimized.yml**: Optimized workflow with caching

To trigger a build:

```bash
# Create a new version tag
./release.sh v5.0-multi9

# Or manually
git tag -a v5.0-multi9 -m "Release v5.0-multi9"
git push origin v5.0-multi9
```

## Version Release

### Using Release Script

```bash
# Show help
./release.sh --help

# Dry run (test without executing)
./release.sh --dry-run v5.0-multi9

# Release with custom message
./release.sh -m "Bug fixes and improvements" v5.0-multi9

# Force release (skip confirmation)
./release.sh --force v5.0-multi9
```

### Manual Release

1. Update `install.sh` TAG version
2. Commit changes
3. Create Git tag
4. Push tag to GitHub
5. Wait for CI to build and create release

```bash
# Update install.sh
sed -i 's/TAG=".*"/TAG="v5.0-multi9"/' install.sh

# Commit
git add install.sh
git commit -m "chore: update install.sh TAG to v5.0-multi9"

# Create tag
git tag -a v5.0-multi9 -m "Release v5.0-multi9"

# Push
git push origin main
git push origin v5.0-multi9
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

Same as OpenTenBase (Apache 2.0).

---

**Maintainer**: muzimu217  
**Last Updated**: 2026-05-20
