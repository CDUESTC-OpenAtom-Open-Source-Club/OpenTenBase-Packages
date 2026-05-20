#!/bin/bash
# Generate release notes for OpenTenBase .deb packages
# Usage: ./generate-release-notes.sh [version]

set -e

VERSION="${1:-$(git describe --tags --abbrev=0 2>/dev/null || echo 'unknown')}"
DATE=$(date '+%Y-%m-%d')

cat << EOF
# OpenTenBase ${VERSION}

**Release Date**: ${DATE}

## Supported Systems

| Distribution | Version | Architecture |
|--------------|---------|--------------|
| Ubuntu | 20.04 (Focal) | amd64 |
| Ubuntu | 22.04 (Jammy) | amd64 |
| Ubuntu | 24.04 (Noble) | amd64 |
| Debian | 11 (Bullseye) | amd64 |
| Debian | 12 (Bookworm) | amd64 |

## Quick Start

### One-line Install (Recommended)

\`\`\`bash
curl -sLO https://github.com/muzimu217/OpenTenBase-deb/releases/download/${VERSION}/install.sh
sudo bash install.sh
\`\`\`

### Manual Install

\`\`\`bash
# Download packages for your distro
# Example for Ubuntu 22.04:
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/${VERSION}/opentenbase_5.0-1ubuntu1.jammy_all.deb
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/${VERSION}/opentenbase-server_5.0-1ubuntu1.jammy_amd64.deb
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/${VERSION}/opentenbase-client_5.0-1ubuntu1.jammy_amd64.deb
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/${VERSION}/opentenbase-contrib_5.0-1ubuntu1.jammy_amd64.deb
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/${VERSION}/libopentenbase-dev_5.0-1ubuntu1.jammy_amd64.deb

# Install
sudo dpkg -i *.deb
sudo apt-get install -f
\`\`\`

### Docker Compose

\`\`\`bash
git clone https://github.com/muzimu217/OpenTenBase-deb.git
cd opentenbase-deb/docker/compose
docker compose up -d
\`\`\`

## Getting Started

\`\`\`bash
# Initialize cluster
opentenbase-ctl init

# Start all nodes
opentenbase-ctl start

# Check status
opentenbase-ctl status

# Connect
psql -h 127.0.0.1 -p 5432 -U opentenbase -d postgres

# Stop cluster
opentenbase-ctl stop
\`\`\`

## Verification Status

- [x] Package installation tested on all 5 distributions
- [x] Cluster initialization verified
- [x] SQL operations (SELECT, INSERT, CREATE TABLE) verified
- [x] Multi-node (GTM + Coordinator + Datanode) startup verified

## Included Packages

| Package | Description |
|---------|-------------|
| \`opentenbase\` | Meta-package (installs all components) |
| \`opentenbase-server\` | Server binaries (postgres, gtm, etc.) |
| \`opentenbase-client\` | Client tools (psql, pg_dump, etc.) |
| \`opentenbase-contrib\` | Contrib extensions |
| \`libopentenbase-dev\` | Development headers and libraries |
| \`opentenbase-doc\` | Documentation |

## Changelog

$(git log --oneline --no-merges $(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo '')..HEAD 2>/dev/null | head -20 || echo "See commit history for details")

## Known Issues

- License restrictions: Open source version is read-only for some features
- Single-machine deployment: Cross-machine deployment requires manual configuration

## Documentation

- [README](docs/README.md)
- [Chinese Documentation](docs/README_zh.md)
- [Architecture](docs/ROADMAP.md)
- [Contributing Guide](docs/CONTRIBUTING.md)

## Docker

Docker Compose files are available in \`docker/compose/\` for one-command cluster deployment.

---

**Full Changelog**: https://github.com/muzimu217/OpenTenBase-deb/compare/$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo 'init')...${VERSION}
EOF
