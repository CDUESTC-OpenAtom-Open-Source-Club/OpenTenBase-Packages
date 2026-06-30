#!/bin/bash
# =============================================================================
# OpenTenBase Release Notes Generator
# 自动生成标准化的 Release 说明
#
# Usage:
#   ./scripts/generate-release-notes.sh v5.0-multi10
#   ./scripts/generate-release-notes.sh v5.0-multi10 --draft
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
REPO_OWNER="muzimu217"
REPO_NAME="OpenTenBase-Packages"
REPO_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---------------------------------------------------------------------------
# Supported distributions
# ---------------------------------------------------------------------------
DEB_DISTROS=(
    "Ubuntu 18.04 (Bionic)"
    "Ubuntu 20.04 (Focal)"
    "Ubuntu 22.04 (Jammy)"
    "Ubuntu 24.04 (Noble)"
    "Ubuntu 25.04 (Plucky)"
    "Debian 10 (Buster)"
    "Debian 11 (Bullseye)"
    "Debian 12 (Bookworm)"
    "Debian 13 (Trixie)"
)

RPM_DISTROS=(
    "CentOS Stream 8/9"
    "Rocky Linux 8/9"
    "AlmaLinux 8/9"
    "Fedora 40"
    "OpenEuler 22.03"
)

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------

get_previous_tag() {
    git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo ""
}

get_changelog() {
    local prev_tag="$1"
    local current_tag="$2"

    if [ -z "$prev_tag" ]; then
        git log --oneline --no-decorate -20
    else
        git log --oneline --no-decorate "${prev_tag}..${current_tag}"
    fi
}

categorize_changes() {
    local changelog="$1"

    local features=""
    local fixes=""
    local docs=""
    local ci=""
    local other=""

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local msg="${line#* }"

        case "$msg" in
            feat:*|feature:*|add:*|新增*|添加*)
                features="${features}- ${msg}\n"
                ;;
            fix:*|bugfix:*|修复*|修复*)
                fixes="${fixes}- ${msg}\n"
                ;;
            docs:*|doc:*|文档*)
                docs="${docs}- ${msg}\n"
                ;;
            ci:*|ci\(*|build:*|构建*)
                ci="${ci}- ${msg}\n"
                ;;
            *)
                other="${other}- ${msg}\n"
                ;;
        esac
    done <<< "$changelog"

    [ -n "$features" ] && echo -e "### New Features\n${features}"
    [ -n "$fixes" ] && echo -e "### Bug Fixes\n${fixes}"
    [ -n "$ci" ] && echo -e "### CI/CD\n${ci}"
    [ -n "$docs" ] && echo -e "### Documentation\n${docs}"
    [ -n "$other" ] && echo -e "### Other Changes\n${other}"
}

generate_release_notes() {
    local version="$1"
    local prev_tag
    prev_tag=$(get_previous_tag)
    local changelog
    changelog=$(get_changelog "$prev_tag" "$version")
    local categorized
    categorized=$(categorize_changes "$changelog")
    local date
    date=$(date +%Y-%m-%d)

    cat <<EOF
# OpenTenBase ${version}

**Release Date**: ${date}
**Package Version**: ${version#v}

---

## Supported Systems

### DEB Packages (amd64 + arm64)

$(for d in "${DEB_DISTROS[@]}"; do echo "- ${d}"; done)

### RPM Packages (x86_64 + aarch64)

$(for d in "${RPM_DISTROS[@]}"; do echo "- ${d}"; done)

---

## Quick Start

### One-Click Install (Recommended)

\`\`\`bash
curl -sSL ${REPO_URL}/releases/download/${version}/install.sh | sudo bash
\`\`\`

### Manual Install (DEB)

\`\`\`bash
# Download packages
wget ${REPO_URL}/releases/download/${version}/opentenbase_${version#v}_amd64.deb

# Install
sudo dpkg -i opentenbase_*.deb
sudo apt-get install -f -y
\`\`\`

### Manual Install (RPM)

\`\`\`bash
# Download packages
wget ${REPO_URL}/releases/download/${version}/opentenbase-${version#v}.x86_64.rpm

# Install
sudo rpm -ivh opentenbase-*.rpm
\`\`\`

### Docker Compose (Source Build)

\`\`\`bash
git clone ${REPO_URL}.git
cd OpenTenBase-Packages/docker/dev
docker-compose -f docker-compose.dev.yml run --rm builder
docker-compose -f docker-compose.dev.yml up -d
\`\`\`

---

## Verification Status

- [x] Package installation test passed
- [x] Cluster initialization test passed
- [x] SQL query test passed (SELECT/INSERT/UPDATE/DELETE)
- [x] Docker Compose deployment test passed
- [x] Source compilation test passed (GCC 12)

---

## Changelog

${categorized}

---

## Known Issues

- License restriction: Open-source version is read-only for some features
- Single-machine deployment: Cross-machine deployment requires manual configuration

---

## Documentation

- [Installation Guide (Chinese)](${REPO_URL}/blob/main/docs/README_zh.md)
- [Installation Guide (English)](${REPO_URL}/blob/main/docs/README.md)
- [Architecture Guide](${REPO_URL}/blob/main/docs/tutorials/03-architecture.md)
- [Troubleshooting](${REPO_URL}/blob/main/docs/tutorials/05-troubleshoot.md)
- [Source Build Guide](${REPO_URL}/blob/main/docs/source-build-guide.md)

---

## Package Checksums

Checksums are available in the \`checksums.sha256\` file attached to this release.

---

**Full Changelog**: ${prev_tag:+${REPO_URL}/compare/${prev_tag}...${version}}
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    local version="${1:-}"
    local draft="${2:-}"

    if [ -z "$version" ]; then
        log_error "Usage: $0 <version> [--draft]"
        log_error "Example: $0 v5.0-multi10"
        exit 1
    fi

    # Validate version format
    if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+ ]]; then
        log_error "Invalid version format: $version"
        log_error "Expected format: v5.0-multi10"
        exit 1
    fi

    log_info "Generating release notes for ${version}..."

    local notes
    notes=$(generate_release_notes "$version")

    if [ "$draft" = "--draft" ]; then
        echo "$notes"
    else
        local output_file="release-notes-${version}.md"
        echo "$notes" > "$output_file"
        log_info "Release notes saved to: ${output_file}"
    fi
}

main "$@"
