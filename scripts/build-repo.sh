#!/bin/bash
# OpenTenBase APT/RPM Repository Builder
# Builds a static APT and RPM repository from GitHub Release assets
# Usage: ./scripts/build-repo.sh [OPTIONS]
#
# Options:
#   -t, --tag TAG       Release tag to use (default: latest)
#   -o, --output DIR    Output directory (default: ./repo)
#   -k, --key-id ID     GPG key ID for signing (default: auto-detect)
#   --no-sign           Skip GPG signing
#   --apt-only          Build APT repo only
#   --rpm-only          Build RPM repo only
#   -h, --help          Show this help

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

REPO_OWNER="muzimu217"
REPO_NAME="OpenTenBase-deb"
GPG_KEY_ID="${GPG_KEY_ID:-9D8FA46F3A55D5F0}"

# DEB codenames
DEB_CODENAMES=(focal jammy noble plucky bullseye bookworm trixie)

# RPM distro patterns -> repo directory mapping
# Format: "pattern:repo_dir"
RPM_DISTROS=(
    "almalinux-8:el8"
    "almalinux-9:el9"
    "centos-stream-8:el8"
    "centos-stream-9:el9"
    "rockylinux-8:el8"
    "rockylinux-9:el9"
    "fedora-40:fedora"
    "openeuler-22.03:openeuler"
)

show_help() {
    head -15 "$0" | grep '^#' | sed 's/^# \?//'
    exit 0
}

check_deps() {
    local missing=()
    for cmd in curl jq dpkg-scanpackages gpg gzip; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_info "Install: sudo apt-get install -y dpkg-dev gnupg jq"
        exit 1
    fi
}

# Download all assets from a release
download_release() {
    local tag=$1
    local outdir=$2

    log_step "Downloading release $tag ..."
    mkdir -p "$outdir"

    local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/tags/${tag}"
    local urls
    urls=$(curl -sL "$api_url" | jq -r '.assets[].browser_download_url')

    if [ -z "$urls" ]; then
        log_error "No assets found for release $tag"
        exit 1
    fi

    local count=0
    while IFS= read -r url; do
        local fname
        fname=$(basename "$url")
        # Skip debuginfo/debugsource RPMs (too large for repo hosting)
        if echo "$fname" | grep -qE 'debuginfo|debugsource'; then
            continue
        fi
        log_info "  $fname"
        curl -sL "$url" -o "$outdir/$fname"
        count=$((count + 1))
    done <<< "$urls"

    log_info "Downloaded $count assets"
}

# Build APT repository structure
build_apt_repo() {
    local pkgdir=$1
    local outdir=$2

    log_step "Building APT repository ..."

    local apt_dir="$outdir/apt"
    mkdir -p "$apt_dir"

    # Copy GPG public key
    if [ -f scripts/opentenbase-packages-key.asc ]; then
        cp scripts/opentenbase-packages-key.asc "$apt_dir/gpg-key.asc"
    fi

    for codename in "${DEB_CODENAMES[@]}"; do
        local codename_dir="$apt_dir/$codename"
        local pool_dir="$codename_dir/pool/main"
        local dist_dir="$codename_dir/dists/$codename"
        local binary_dir="$dist_dir/main/binary-amd64"

        mkdir -p "$pool_dir" "$binary_dir"

        # Find and copy DEBs for this codename
        local debs
        debs=$(find "$pkgdir" \( -name "*.${codename}_*.deb" -o -name "*.${codename}.*.deb" \) 2>/dev/null || true)

        if [ -z "$debs" ]; then
            log_warn "No DEB packages found for $codename, skipping"
            continue
        fi

        local count=0
        while IFS= read -r deb; do
            [ -f "$deb" ] || continue
            cp "$deb" "$pool_dir/"
            count=$((count + 1))
        done <<< "$debs"

        log_info "  $codename: $count packages"

        # Generate Packages file
        cd "$pool_dir"
        dpkg-scanpackages . /dev/null 2>/dev/null > "$binary_dir/Packages" || {
            log_warn "dpkg-scanpackages failed for $codename"
            cd - > /dev/null
            continue
        }
        gzip -9c "$binary_dir/Packages" > "$binary_dir/Packages.gz"
        cd - > /dev/null

        # Generate Release file for this codename
        cat > "$dist_dir/Release" << EOF
Origin: OpenTenBase
Label: OpenTenBase
Suite: $codename
Codename: $codename
Architectures: amd64
Components: main
Description: OpenTenBase packages for $codename
Date: $(date -Ru)
EOF

        # Add checksums to Release
        echo "MD5Sum:" >> "$dist_dir/Release"
        for f in "$binary_dir/Packages" "$binary_dir/Packages.gz"; do
            [ -f "$f" ] || continue
            local fname
            fname=$(basename "$f")
            local md5
            md5=$(md5sum "$f" | cut -d' ' -f1)
            local size
            size=$(wc -c < "$f" | tr -d ' ')
            echo " $md5 $size main/binary-amd64/$fname" >> "$dist_dir/Release"
        done

        echo "SHA256:" >> "$dist_dir/Release"
        for f in "$binary_dir/Packages" "$binary_dir/Packages.gz"; do
            [ -f "$f" ] || continue
            local fname
            fname=$(basename "$f")
            local sha
            sha=$(sha256sum "$f" | cut -d' ' -f1)
            local size
            size=$(wc -c < "$f" | tr -d ' ')
            echo " $sha $size main/binary-amd64/$fname" >> "$dist_dir/Release"
        done

        # Sign Release file
        if [ "$NO_SIGN" != "true" ] && command -v gpg &>/dev/null; then
            log_info "  Signing Release for $codename ..."
            gpg --batch --yes --armor \
                --local-user "$GPG_KEY_ID" \
                --detach-sign \
                --output "$dist_dir/Release.gpg" \
                "$dist_dir/Release" 2>/dev/null || log_warn "GPG signing failed for $codename"

            # Create inline-signed InRelease
            gpg --batch --yes --armor \
                --local-user "$GPG_KEY_ID" \
                --clearsign \
                --output "$dist_dir/InRelease" \
                "$dist_dir/Release" 2>/dev/null || log_warn "InRelease signing failed for $codename"
        fi
    done

    log_info "APT repository built at: $apt_dir"
}

# Build RPM repository structure
build_rpm_repo() {
    local pkgdir=$1
    local outdir=$2

    log_step "Building RPM repository ..."

    local rpm_dir="$outdir/rpm"

    # Copy GPG public key
    if [ -f scripts/opentenbase-packages-key.asc ]; then
        cp scripts/opentenbase-packages-key.asc "$rpm_dir/gpg-key.asc"
    fi

    for distro_entry in "${RPM_DISTROS[@]}"; do
        local pattern="${distro_entry%%:*}"
        local repo_subdir="${distro_entry##*:}"
        local arch="x86_64"

        # Detect aarch64 packages
        local aarch64_rpms
        aarch64_rpms=$(find "$pkgdir" -name "*.${pattern}-aarch64.*.rpm" 2>/dev/null || true)

        for target_arch in x86_64; do
            local rpms
            rpms=$(find "$pkgdir" -name "*.${pattern}-${target_arch}.*.rpm" 2>/dev/null || true)

            if [ -z "$rpms" ]; then
                continue
            fi

            local arch_dir="$rpm_dir/$repo_subdir/$target_arch"
            mkdir -p "$arch_dir"

            local count=0
            while IFS= read -r rpm; do
                [ -f "$rpm" ] || continue
                cp "$rpm" "$arch_dir/"
                count=$((count + 1))
            done <<< "$rpms"

            log_info "  $repo_subdir/$target_arch: $count packages"

            # Generate repo metadata if createrepo_c is available
            if command -v createrepo_c &>/dev/null; then
                createrepo_c "$arch_dir" 2>/dev/null || {
                    # Fallback: create minimal repomd.xml
                    log_warn "createrepo_c failed, creating minimal metadata"
                    create_minimal_rpm_metadata "$arch_dir"
                }
            else
                log_warn "createrepo_c not found, creating minimal metadata"
                create_minimal_rpm_metadata "$arch_dir"
            fi
        done

        # Also handle aarch64
        if [ -n "$aarch64_rpms" ]; then
            local arch_dir="$rpm_dir/$repo_subdir/aarch64"
            mkdir -p "$arch_dir"

            local count=0
            while IFS= read -r rpm; do
                [ -f "$rpm" ] || continue
                cp "$rpm" "$arch_dir/"
                count=$((count + 1))
            done <<< "$aarch64_rpms"

            log_info "  $repo_subdir/aarch64: $count packages"

            if command -v createrepo_c &>/dev/null; then
                createrepo_c "$arch_dir" 2>/dev/null || create_minimal_rpm_metadata "$arch_dir"
            else
                create_minimal_rpm_metadata "$arch_dir"
            fi
        fi
    done

    # Sign repomd.xml files
    if [ "$NO_SIGN" != "true" ] && command -v gpg &>/dev/null; then
        find "$rpm_dir" -name "repomd.xml" | while read -r repomd; do
            log_info "  Signing $repomd ..."
            gpg --batch --yes --armor \
                --local-user "$GPG_KEY_ID" \
                --detach-sign \
                --output "${repomd}.asc" \
                "$repomd" 2>/dev/null || log_warn "Signing failed: $repomd"
        done
    fi

    log_info "RPM repository built at: $rpm_dir"
}

# Create minimal RPM repo metadata (fallback when createrepo_c is not available)
create_minimal_rpm_metadata() {
    local dir=$1
    local repodata_dir="$dir/repodata"
    mkdir -p "$repodata_dir"

    # Create a minimal repomd.xml
    cat > "$repodata_dir/repomd.xml" << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<repomd xmlns="http://linux.duke.edu/metadata/repo">
</repomd>
XMLEOF

    log_warn "  Minimal RPM metadata created (install createrepo_c for full metadata)"
}

# Create index page for GitHub Pages
create_index_page() {
    local outdir=$1

    cat > "$outdir/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>OpenTenBase Packages Repository</title>
    <style>
        body { font-family: -apple-system, sans-serif; max-width: 800px; margin: 40px auto; padding: 0 20px; line-height: 1.6; }
        h1 { color: #333; }
        pre { background: #f5f5f5; padding: 15px; border-radius: 5px; overflow-x: auto; }
        .section { margin: 30px 0; }
        a { color: #0366d6; }
    </style>
</head>
<body>
    <h1>OpenTenBase Packages Repository</h1>
    <p>Official APT and RPM repository for <a href="https://github.com/OpenTenBase/OpenTenBase">OpenTenBase</a>.</p>

    <div class="section">
        <h2>DEB (Ubuntu / Debian)</h2>
        <pre>curl -sSL https://raw.githubusercontent.com/muzimu217/OpenTenBase-deb/main/scripts/setup-apt.sh | sudo bash
sudo apt update
sudo apt install opentenbase</pre>
    </div>

    <div class="section">
        <h2>RPM (RHEL / CentOS / Fedora)</h2>
        <pre>curl -sSL https://raw.githubusercontent.com/muzimu217/OpenTenBase-deb/main/scripts/setup-rpm.sh | sudo bash
sudo dnf install opentenbase</pre>
    </div>

    <div class="section">
        <h2>Links</h2>
        <ul>
            <li><a href="https://github.com/muzimu217/OpenTenBase-deb">GitHub Repository</a></li>
            <li><a href="https://github.com/muzimu217/OpenTenBase-deb/releases">Releases</a></li>
            <li><a href="https://github.com/OpenTenBase/OpenTenBase">OpenTenBase Upstream</a></li>
        </ul>
    </div>
</body>
</html>
EOF
}

# ============================================================
# Main
# ============================================================
TAG=""
OUTPUT_DIR="./repo"
NO_SIGN="false"
BUILD_APT="true"
BUILD_RPM="true"

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tag)       TAG="$2"; shift 2 ;;
        -o|--output)    OUTPUT_DIR="$2"; shift 2 ;;
        -k|--key-id)    GPG_KEY_ID="$2"; shift 2 ;;
        --no-sign)      NO_SIGN="true"; shift ;;
        --apt-only)     BUILD_RPM="false"; shift ;;
        --rpm-only)     BUILD_APT="false"; shift ;;
        -h|--help)      show_help ;;
        *)              log_error "Unknown option: $1"; show_help ;;
    esac
done

echo "========================================"
echo "  OpenTenBase Repository Builder"
echo "========================================"
echo ""

check_deps

# Get latest tag if not specified
if [ -z "$TAG" ]; then
    TAG=$(curl -sL "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest" | jq -r '.tag_name // empty')
    if [ -z "$TAG" ]; then
        log_error "Could not determine latest release tag"
        exit 1
    fi
fi

log_info "Release: $TAG"
log_info "Output:  $OUTPUT_DIR"
log_info "GPG Key: $GPG_KEY_ID"
echo ""

# Download packages
DOWNLOAD_DIR=$(mktemp -d)
trap 'rm -rf "$DOWNLOAD_DIR"' EXIT
download_release "$TAG" "$DOWNLOAD_DIR"

# Build repos
if [ "$BUILD_APT" = "true" ]; then
    build_apt_repo "$DOWNLOAD_DIR" "$OUTPUT_DIR"
fi

if [ "$BUILD_RPM" = "true" ]; then
    build_rpm_repo "$DOWNLOAD_DIR" "$OUTPUT_DIR"
fi

# Create index page
create_index_page "$OUTPUT_DIR"

echo ""
echo "========================================"
log_info "Repository build complete!"
echo "========================================"
echo ""
echo "Output directory: $OUTPUT_DIR"
echo ""
echo "Next steps:"
echo "  1. Test locally: cd $OUTPUT_DIR && python3 -m http.server 8080"
echo "  2. Deploy to GitHub Pages (CI does this automatically)"
echo ""
