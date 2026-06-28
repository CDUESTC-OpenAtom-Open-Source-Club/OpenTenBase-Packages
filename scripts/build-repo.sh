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

REPO_OWNER="CDUESTC-OpenAtom-Open-Source-Club"
REPO_NAME="OpenTenBase-Packages"
GPG_KEY_ID="${GPG_KEY_ID:-9D8FA46F3A55D5F0}"

# DEB codenames
DEB_CODENAMES=(focal jammy noble plucky bullseye bookworm trixie)

# Version -> APT component mapping
# The latest/default version uses "main"; older versions get their own component.
# Users add components to sources.list to access specific versions.
# Format: "version:component"
DEB_VERSION_COMPONENTS=(
    "5.0:main"
    "2.6.0:v2.6"
    "2.5.0:v2.5"
)

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

    # Use gh CLI for reliable download (handles pagination, auth, retries)
    if command -v gh &>/dev/null; then
        log_info "Using gh CLI to download assets ..."
        gh release download "$tag" \
            --repo "${REPO_OWNER}/${REPO_NAME}" \
            --dir "$outdir" \
            --skip-existing 2>&1 || true
        # Remove debuginfo/debugsource RPMs (too large for repo hosting)
        find "$outdir" -name '*debuginfo*' -o -name '*debugsource*' | xargs rm -f 2>/dev/null || true
        local count
        count=$(find "$outdir" -type f | wc -l)
        log_info "Downloaded $count assets"
    else
        # Fallback: use API with pagination
        local page=1
        local all_urls=""
        while true; do
            local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/tags/${tag}?per_page=100&page=${page}"
            local curl_args=(-sL)
            if [ -n "${GITHUB_TOKEN:-}" ]; then
                curl_args+=(-H "Authorization: token $GITHUB_TOKEN")
            fi
            local page_urls
            page_urls=$(curl "${curl_args[@]}" "$api_url" | jq -r '.assets[].browser_download_url // empty')
            if [ -z "$page_urls" ]; then
                break
            fi
            all_urls="${all_urls}${page_urls}"$'\n'
            page=$((page + 1))
        done

        if [ -z "$all_urls" ]; then
            log_error "No assets found for release $tag"
            exit 1
        fi

        local count=0
        while IFS= read -r url; do
            [ -z "$url" ] && continue
            local fname
            fname=$(basename "$url")
            if echo "$fname" | grep -qE 'debuginfo|debugsource'; then
                continue
            fi
            log_info "  $fname"
            curl -sL "$url" -o "$outdir/$fname"
            count=$((count + 1))
        done <<< "$all_urls"

        log_info "Downloaded $count assets"
    fi
}

# Build APT repository structure
# Uses components as version selectors:
#   main  -> v5.0 (latest, default)
#   v2.6  -> v2.6.0
#   v2.5  -> v2.5.0
# Each component has its own pool/ and Packages file, so dpkg-scanpackages
# doesn't deduplicate across versions (same package name, different versions).
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
        local dist_dir="$apt_dir/dists/$codename"
        local components_for_codename=()
        local has_packages=false

        # Process each version -> component mapping
        for vc_entry in "${DEB_VERSION_COMPONENTS[@]}"; do
            local version="${vc_entry%%:*}"
            local component="${vc_entry##*:}"
            local component_pool="$apt_dir/pool/$component/$codename"
            local binary_dir="$dist_dir/$component/binary-amd64"

            mkdir -p "$binary_dir" "$component_pool"

            # Find DEBs matching this codename AND version
            local debs
            debs=$(find "$pkgdir" \( -name "*~${codename}_*.deb" -o -name "*.${codename}_*.deb" -o -name "*.${codename}.*.deb" \) 2>/dev/null | grep "_${version}-" || true)

            if [ -z "$debs" ]; then
                continue
            fi

            local count=0
            while IFS= read -r deb; do
                [ -f "$deb" ] || continue
                cp "$deb" "$component_pool/"
                count=$((count + 1))
            done <<< "$debs"

            log_info "  $codename/$component (v$version): $count packages"
            components_for_codename+=("$component")
            has_packages=true

            # Generate Packages file
            local abs_binary_dir
            abs_binary_dir="$(cd "$binary_dir" && pwd)"
            local filename_prefix="pool/$component/$codename"
            if ! dpkg-scanpackages "$component_pool" /dev/null 2>/dev/null | \
                sed "s|^Filename: $component_pool/|Filename: $filename_prefix/|" > "$abs_binary_dir/Packages"; then
                log_warn "dpkg-scanpackages failed for $codename/$component"
                dpkg-scanpackages "$component_pool" /dev/null 2>/dev/null | \
                    sed "s|^Filename: $component_pool/|Filename: $filename_prefix/|" > "$abs_binary_dir/Packages" || continue
            fi
            gzip -9c "$abs_binary_dir/Packages" > "$abs_binary_dir/Packages.gz"
        done

        if [ "$has_packages" != "true" ]; then
            log_warn "No DEB packages found for $codename, skipping"
            continue
        fi

        # Generate Release file listing all components
        local component_list="${components_for_codename[*]}"
        mkdir -p "$dist_dir"
        cat > "$dist_dir/Release" << EOF
Origin: OpenTenBase
Label: OpenTenBase
Suite: $codename
Codename: $codename
Architectures: amd64
Components: $component_list
Description: OpenTenBase packages for $codename
Date: $(date -Ru)
EOF

        # Add checksums for all components
        echo "MD5Sum:" >> "$dist_dir/Release"
        for comp in "${components_for_codename[@]}"; do
            for f in "$dist_dir/$comp/binary-amd64/Packages" "$dist_dir/$comp/binary-amd64/Packages.gz"; do
                [ -f "$f" ] || continue
                local fname
                fname=$(basename "$f")
                local md5
                md5=$(md5sum "$f" | cut -d' ' -f1)
                local size
                size=$(wc -c < "$f" | tr -d ' ')
                echo " $md5 $size $comp/binary-amd64/$fname" >> "$dist_dir/Release"
            done
        done

        echo "SHA256:" >> "$dist_dir/Release"
        for comp in "${components_for_codename[@]}"; do
            for f in "$dist_dir/$comp/binary-amd64/Packages" "$dist_dir/$comp/binary-amd64/Packages.gz"; do
                [ -f "$f" ] || continue
                local fname
                fname=$(basename "$f")
                local sha
                sha=$(sha256sum "$f" | cut -d' ' -f1)
                local size
                size=$(wc -c < "$f" | tr -d ' ')
                echo " $sha $size $comp/binary-amd64/$fname" >> "$dist_dir/Release"
            done
        done

        # Sign Release file
        if [ "$NO_SIGN" != "true" ] && command -v gpg &>/dev/null; then
            # Verify the signing key is available
            if ! gpg --list-secret-keys "$GPG_KEY_ID" &>/dev/null; then
                log_error "GPG secret key $GPG_KEY_ID not found in keyring"
                log_error "Set the GPG_PRIVATE_KEY secret in GitHub Settings -> Secrets"
                log_error "Or run with --no-sign to skip signing"
                exit 1
            fi

            log_info "  Signing Release for $codename ..."
            if ! gpg --batch --yes --armor \
                --local-user "$GPG_KEY_ID" \
                --detach-sign \
                --output "$dist_dir/Release.gpg" \
                "$dist_dir/Release"; then
                log_error "Failed to create Release.gpg for $codename"
                exit 1
            fi

            # Create inline-signed InRelease
            if ! gpg --batch --yes --armor \
                --local-user "$GPG_KEY_ID" \
                --clearsign \
                --output "$dist_dir/InRelease" \
                "$dist_dir/Release"; then
                log_error "Failed to create InRelease for $codename"
                exit 1
            fi

            log_info "  Release signed successfully for $codename"
        else
            if [ "$NO_SIGN" != "true" ]; then
                log_warn "GPG not available, repository will be unsigned"
            fi
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
    mkdir -p "$rpm_dir"

    # Copy GPG public key
    if [ -f scripts/opentenbase-packages-key.asc ]; then
        cp scripts/opentenbase-packages-key.asc "$rpm_dir/gpg-key.asc"
    fi

    for distro_entry in "${RPM_DISTROS[@]}"; do
        local pattern="${distro_entry%%:*}"
        local repo_subdir="${distro_entry##*:}"
        local arch="x86_64"

        # Detect aarch64 packages (filename pattern: *.<distro>-<ver>-aarch64.*.rpm)
        local aarch64_rpms
        aarch64_rpms=$(find "$pkgdir" -name "*${pattern}*aarch64*.rpm" 2>/dev/null || true)

        for target_arch in x86_64; do
            local rpms
            rpms=$(find "$pkgdir" -name "*${pattern}*${target_arch}*.rpm" ! -name "*aarch64*" 2>/dev/null || true)

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

# Create index pages for GitHub Pages (root + subdirectories)
create_index_page() {
    local outdir=$1

    # Root index.html
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
        <pre>curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-apt.sh | sudo bash
sudo apt update
sudo apt install opentenbase</pre>
    </div>

    <div class="section">
        <h2>RPM (RHEL / CentOS / Fedora)</h2>
        <pre>curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-rpm.sh | sudo bash
sudo dnf install opentenbase</pre>
    </div>

    <div class="section">
        <h2>Links</h2>
        <ul>
            <li><a href="https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages">GitHub Repository</a></li>
            <li><a href="https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases">Releases</a></li>
            <li><a href="https://github.com/OpenTenBase/OpenTenBase">OpenTenBase Upstream</a></li>
        </ul>
    </div>
</body>
</html>
EOF

    # Subdirectory index pages (GitHub Pages doesn't auto-list directories)
    mkdir -p "$outdir/apt" "$outdir/rpm"

    cat > "$outdir/apt/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>OpenTenBase APT Repository</title>
    <style>
        body { font-family: -apple-system, sans-serif; max-width: 800px; margin: 40px auto; padding: 0 20px; line-height: 1.6; }
        h1 { color: #333; }
        pre { background: #f5f5f5; padding: 15px; border-radius: 5px; overflow-x: auto; }
        a { color: #0366d6; }
    </style>
</head>
<body>
    <h1>OpenTenBase APT Repository</h1>
    <p>APT repository for Ubuntu and Debian.</p>
    <h2>Quick Install</h2>
    <pre>curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-apt.sh | sudo bash
sudo apt update
sudo apt install opentenbase</pre>
    <h2>Repository Structure</h2>
    <ul>
EOF

    # Dynamically list codename directories
    for codename_dir in "$outdir/apt"/*/; do
        [ -d "$codename_dir" ] || continue
        local codename
        codename=$(basename "$codename_dir")
        [ "$codename" = "index.html" ] && continue
        echo "        <li><a href=\"$codename/\">$codename</a></li>" >> "$outdir/apt/index.html"
    done

    cat >> "$outdir/apt/index.html" << 'EOF'
    </ul>
    <p><a href="../">Back to repository home</a></p>
</body>
</html>
EOF

    cat > "$outdir/rpm/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>OpenTenBase RPM Repository</title>
    <style>
        body { font-family: -apple-system, sans-serif; max-width: 800px; margin: 40px auto; padding: 0 20px; line-height: 1.6; }
        h1 { color: #333; }
        pre { background: #f5f5f5; padding: 15px; border-radius: 5px; overflow-x: auto; }
        a { color: #0366d6; }
    </style>
</head>
<body>
    <h1>OpenTenBase RPM Repository</h1>
    <p>RPM repository for RHEL, CentOS, Rocky, Alma, Fedora, and openEuler.</p>
    <h2>Quick Install</h2>
    <pre>curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-rpm.sh | sudo bash
sudo dnf install opentenbase</pre>
    <h2>Repository Structure</h2>
    <ul>
EOF

    # Dynamically list distro/arch directories
    for distro_dir in "$outdir/rpm"/*/; do
        [ -d "$distro_dir" ] || continue
        local distro
        distro=$(basename "$distro_dir")
        [ "$distro" = "index.html" ] && continue
        echo "        <li><a href=\"$distro/\">$distro</a></li>" >> "$outdir/rpm/index.html"
    done

    cat >> "$outdir/rpm/index.html" << 'EOF'
    </ul>
    <p><a href="../">Back to repository home</a></p>
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

# Sign downloaded packages (package-level GPG signature, not just repo metadata)
# This is required for gpgcheck=1 in the repo config to work — without package
# signatures, dnf/apt reject installation even though repomd.xml is signed.
sign_downloaded_packages() {
    local dir="$1"

    if [ "$NO_SIGN" = "true" ]; then
        log_warn "Skipping package signing (--no-sign)"
        return 0
    fi

    if ! command -v gpg &>/dev/null; then
        log_warn "gpg not available, packages will be unsigned"
        return 0
    fi

    # Verify the signing key is available
    if ! gpg --list-secret-keys "$GPG_KEY_ID" &>/dev/null; then
        log_warn "GPG key $GPG_KEY_ID not in keyring, packages will be unsigned"
        return 0
    fi

    local rpm_count deb_count
    rpm_count=$(find "$dir" -name '*.rpm' 2>/dev/null | wc -l)
    deb_count=$(find "$dir" -name '*.deb' 2>/dev/null | wc -l)
    log_info "Signing $rpm_count RPM + $deb_count DEB packages ..."

    # Sign RPM packages with rpmsign
    if [ "$rpm_count" -gt 0 ]; then
        if command -v rpmsign &>/dev/null; then
            find "$dir" -name '*.rpm' -print0 | while IFS= read -r -d '' rpm; do
                rpmsign --addsign --define "_gpg_name $GPG_KEY_ID" "$rpm" 2>/dev/null \
                    && log_info "  Signed: $(basename "$rpm")" \
                    || log_warn "  Sign failed: $(basename "$rpm")"
            done
        else
            log_warn "rpmsign not available, RPM packages will be unsigned"
        fi
    fi

    # Sign DEB packages with dpkg-sig
    if [ "$deb_count" -gt 0 ]; then
        if command -v dpkg-sig &>/dev/null; then
            find "$dir" -name '*.deb' -print0 | while IFS= read -r -d '' deb; do
                dpkg-sig --sign builder -k "$GPG_KEY_ID" "$deb" 2>/dev/null \
                    && log_info "  Signed: $(basename "$deb")" \
                    || log_warn "  Sign failed: $(basename "$deb")"
            done
        else
            log_warn "dpkg-sig not available, DEB packages will be unsigned"
        fi
    fi

    log_info "Package signing complete"
}

sign_downloaded_packages "$DOWNLOAD_DIR"

# Build repos
if [ "$BUILD_APT" = "true" ]; then
    build_apt_repo "$DOWNLOAD_DIR" "$OUTPUT_DIR"
fi

if [ "$BUILD_RPM" = "true" ]; then
    build_rpm_repo "$DOWNLOAD_DIR" "$OUTPUT_DIR"
fi

# Create index page
create_index_page "$OUTPUT_DIR"

# CNAME file for custom domain (Cloudflare proxied)
echo "repo.blackevil217.com" > "$OUTPUT_DIR/CNAME"

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
