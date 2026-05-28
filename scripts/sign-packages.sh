#!/bin/bash
# OpenTenBase GPG Package Signing Script
# Signs DEB and RPM packages for release distribution.
#
# Supports two modes:
#   1. Interactive (local use)  - generates keys, signs manually
#   2. CI mode (--ci)           - reads GPG key from env vars, non-interactive
#
# Environment variables (CI mode):
#   GPG_PRIVATE_KEY   - ASCII-armored GPG private key (required)
#   GPG_PASSPHRASE    - Passphrase for the GPG key (optional if key has no passphrase)
#
# Usage:
#   ./sign-packages.sh --ci --deb-dir ./debs --rpm-dir ./rpms
#   ./sign-packages.sh -k KEYID -p ./packages
#   ./sign-packages.sh --generate
#   ./sign-packages.sh --export public.key

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC}  $1"; }

# ── Help ──────────────────────────────────────────────────────────────────────
show_help() {
    cat <<'HELP'
OpenTenBase GPG Package Signing Script

Usage: ./sign-packages.sh [OPTIONS]

Modes:
  --ci                   CI mode: import key from GPG_PRIVATE_KEY env var (non-interactive)
  --generate             Generate a new GPG key pair (interactive)
  --list                 List GPG keys in the keyring

Signing options:
  --deb-dir DIR          Directory containing .deb packages to sign
  --rpm-dir DIR          Directory containing .rpm packages to sign
  -k, --key KEYID        GPG key ID to use for signing (default: first available)
  --output-dir DIR       Directory to write signed packages (default: sign in-place)

Key management:
  --export FILE          Export public key to FILE
  --import               Import key from GPG_PRIVATE_KEY env var (same as --ci but without signing)

Verification:
  --verify-deb DIR       Verify DEB signatures in DIR
  --verify-rpm DIR       Verify RPM signatures in DIR

Other:
  -h, --help             Show this help message

Examples:
  # CI: sign all packages using env var
  GPG_PRIVATE_KEY="$(cat key.asc)" ./sign-packages.sh --ci --deb-dir ./debs --rpm-dir ./rpms

  # Local: sign DEB packages with a specific key
  ./sign-packages.sh -k ABCD1234 --deb-dir ./packages

  # Generate a new key pair
  ./sign-packages.sh --generate

  # Export public key for distribution
  ./sign-packages.sh --export opentenbase-gpg-key.asc

  # Verify signatures
  ./sign-packages.sh --verify-deb ./debs --verify-rpm ./rpms
HELP
}

# ── GPG setup for CI ─────────────────────────────────────────────────────────
setup_gpg_from_env() {
    if [ -z "${GPG_PRIVATE_KEY:-}" ]; then
        log_error "GPG_PRIVATE_KEY environment variable is not set"
        log_error "Export your ASCII-armored GPG private key as GPG_PRIVATE_KEY"
        return 1
    fi

    log_step "Importing GPG key from environment..."

    # Create a temporary GNUPGHOME so we don't pollute the system keyring
    export GNUPGHOME
    GNUPGHOME=$(mktemp -d -t opentenbase-gpg-XXXXXX)
    chmod 700 "$GNUPGHOME"

    # Import the private key
    echo "$GPG_PRIVATE_KEY" | gpg --batch --import 2>&1

    # If a passphrase is provided, configure gpg-agent to use it non-interactively
    if [ -n "${GPG_PASSPHRASE:-}" ]; then
        mkdir -p "$GNUPGHOME"
        cat > "$GNUPGHOME/gpg-agent.conf" <<EOF
allow-preset-passphrase
default-cache-ttl 3600
max-cache-ttl 86400
EOF
        # Restart gpg-agent with the new config
        gpgconf --kill gpg-agent 2>/dev/null || true
        gpgconf --launch gpg-agent 2>/dev/null || true

        # Preset the passphrase for the key grip(s)
        gpg --batch --list-secret-keys --with-keygrip 2>/dev/null \
            | grep -A1 'Keygrip' \
            | grep -v 'Keygrip' \
            | while read -r grip; do
                if [ -n "$grip" ] && [ ${#grip} -eq 40 ]; then
                    /usr/lib/gnupg/gpg-preset-passphrase \
                        --preset --passphrase "$GPG_PASSPHRASE" "$grip" 2>/dev/null \
                    || echo "$GPG_PASSPHRASE" \
                        | gpg --batch --pinentry-mode loopback \
                               --passphrase-fd 0 \
                               --list-secret-keys >/dev/null 2>&1 \
                    || true
                fi
            done
    fi

    # Configure gpg for batch operation with optional passphrase
    cat > "$GNUPGHOME/gpg.conf" <<'EOF'
batch
no-tty
pinentry-mode loopback
EOF

    # Get the key ID
    GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format long 2>/dev/null \
        | grep -oP '(?<=sec\s+)[a-z0-9]+/[A-Z0-9]+' \
        | head -1 \
        | cut -d'/' -f2)

    if [ -z "$GPG_KEY_ID" ]; then
        # Fallback: try without grep -P (macOS)
        GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format long 2>/dev/null \
            | grep 'sec' \
            | head -1 \
            | sed 's|.*/||' \
            | awk '{print $1}')
    fi

    if [ -z "$GPG_KEY_ID" ]; then
        log_error "Failed to extract key ID after import"
        gpg --list-secret-keys --keyid-format long 2>&1 || true
        return 1
    fi

    log_info "Imported GPG key: $GPG_KEY_ID"

    # Trust the key ultimately so signing doesn't prompt
    echo "${GPG_KEY_ID}:6:" | gpg --batch --import-ownertrust 2>/dev/null || true

    # Set the passphrase file for rpmsign
    if [ -n "${GPG_PASSPHRASE:-}" ]; then
        RPM_PASSPHRASE_FILE="$GNUPGHOME/.passphrase"
        echo "$GPG_PASSPHRASE" > "$RPM_PASSPHRASE_FILE"
        chmod 600 "$RPM_PASSPHRASE_FILE"
    fi
}

# ── Install signing tools ────────────────────────────────────────────────────
install_signing_tools_deb() {
    if command -v dpkg-sig &>/dev/null; then
        return 0
    fi
    log_info "Installing dpkg-sig..."
    apt-get update -qq && apt-get install -y -qq dpkg-sig 2>/dev/null || {
        log_warn "dpkg-sig not available; falling back to debsigs or gpg detached signatures"
    }
}

install_signing_tools_rpm() {
    if command -v rpmsign &>/dev/null; then
        return 0
    fi
    log_info "Installing rpmsign..."
    if command -v dnf &>/dev/null; then
        dnf install -y rpm-sign 2>/dev/null || true
    elif command -v yum &>/dev/null; then
        yum install -y rpm-sign 2>/dev/null || true
    elif command -v apt-get &>/dev/null; then
        apt-get install -y -qq rpm 2>/dev/null || true
    fi
}

# ── Sign DEB packages ────────────────────────────────────────────────────────
sign_debs() {
    local deb_dir="$1"
    local key_id="${2:-}"
    local output_dir="${3:-}"

    if [ ! -d "$deb_dir" ]; then
        log_error "DEB directory does not exist: $deb_dir"
        return 1
    fi

    local deb_files=("$deb_dir"/*.deb)
    if [ ! -e "${deb_files[0]}" ]; then
        log_warn "No .deb files found in $deb_dir"
        return 0
    fi

    log_step "Signing DEB packages in $deb_dir..."

    # Determine output location
    local target_dir="$deb_dir"
    if [ -n "$output_dir" ]; then
        mkdir -p "$output_dir"
        target_dir="$output_dir"
    fi

    # Try dpkg-sig first, fall back to debsigs, then to gpg detached sigs
    local sign_tool=""
    if command -v dpkg-sig &>/dev/null; then
        sign_tool="dpkg-sig"
    elif command -v debsigs &>/dev/null; then
        sign_tool="debsigs"
    else
        sign_tool="gpg-detach"
    fi

    local count=0
    local failed=0

    for deb in "$deb_dir"/*.deb; do
        [ -f "$deb" ] || continue
        local base
        base=$(basename "$deb")
        local target_file="$target_dir/$base"

        # Copy to output dir if needed
        if [ "$target_dir" != "$deb_dir" ] && [ ! -f "$target_file" ]; then
            cp "$deb" "$target_file"
        fi

        log_info "Signing: $base (tool: $sign_tool)"

        case "$sign_tool" in
            dpkg-sig)
                local sig_args=(--sign builder)
                if [ -n "$key_id" ]; then
                    sig_args+=(-k "$key_id")
                fi
                if dpkg-sig "${sig_args[@]}" "$target_file" 2>&1; then
                    ((count++))
                else
                    log_error "Failed to sign: $base"
                    ((failed++))
                fi
                ;;
            debsigs)
                local sig_args=(--sign=origin)
                if [ -n "$key_id" ]; then
                    sig_args+=(--gpg-opts="-u $key_id --batch --yes --pinentry-mode loopback")
                    if [ -n "${GPG_PASSPHRASE:-}" ]; then
                        sig_args+=(--gpg-opts="-u $key_id --batch --yes --pinentry-mode loopback --passphrase-fd 0")
                        echo "$GPG_PASSPHRASE" | debsigs "${sig_args[@]}" "$target_file" 2>&1 && ((count++)) || ((failed++))
                    else
                        debsigs "${sig_args[@]}" "$target_file" 2>&1 && ((count++)) || ((failed++))
                    fi
                else
                    debsigs "${sig_args[@]}" "$target_file" 2>&1 && ((count++)) || ((failed++))
                fi
                ;;
            gpg-detach)
                # Fallback: create a detached GPG signature alongside the .deb
                local sig_file="$target_file.sig"
                local gpg_args=(--batch --yes --armor --detach-sign)
                if [ -n "$key_id" ]; then
                    gpg_args+=(-u "$key_id")
                fi
                if [ -n "${GPG_PASSPHRASE:-}" ]; then
                    gpg_args+=(--pinentry-mode loopback --passphrase-fd 0)
                    echo "$GPG_PASSPHRASE" | gpg "${gpg_args[@]}" --output "$sig_file" "$target_file" 2>&1 && ((count++)) || ((failed++))
                else
                    gpg "${gpg_args[@]}" --output "$sig_file" "$target_file" 2>&1 && ((count++)) || ((failed++))
                fi
                log_info "  -> $sig_file"
                ;;
        esac
    done

    log_info "DEB signing complete: $count signed, $failed failed"
    [ "$failed" -eq 0 ] || return 1
}

# ── Sign RPM packages ────────────────────────────────────────────────────────
sign_rpms() {
    local rpm_dir="$1"
    local key_id="${2:-}"
    local output_dir="${3:-}"

    if [ ! -d "$rpm_dir" ]; then
        log_error "RPM directory does not exist: $rpm_dir"
        return 1
    fi

    local rpm_files=("$rpm_dir"/*.rpm)
    if [ ! -e "${rpm_files[0]}" ]; then
        log_warn "No .rpm files found in $rpm_dir"
        return 0
    fi

    log_step "Signing RPM packages in $rpm_dir..."

    # Ensure rpmsign is available
    install_signing_tools_rpm

    # Determine output location
    local target_dir="$rpm_dir"
    if [ -n "$output_dir" ]; then
        mkdir -p "$output_dir"
        target_dir="$output_dir"
    fi

    # Configure RPM macros for signing
    local macro_file=""
    if [ -n "$key_id" ]; then
        macro_file="$HOME/.rpmmacros"
        # Backup existing macros
        [ ! -f "$macro_file" ] || cp "$macro_file" "$macro_file.bak"

        cat > "$macro_file" <<EOF
%_signature gpg
%_gpg_name $key_id
%_gpg_path ${GNUPGHOME:-$HOME/.gnupg}
%__gpg_sign_cmd %{__gpg} gpg --batch --no-verbose --no-armor \
    ${GPG_PASSPHRASE:+--pinentry-mode loopback --passphrase-fd 0} \
    ${key_id:+-u "$key_id"} \
    --no-secmem-warning -sbo %{__signature_filename} %{__plaintext_filename}
EOF
    fi

    local count=0
    local failed=0

    for rpm in "$rpm_dir"/*.rpm; do
        [ -f "$rpm" ] || continue
        local base
        base=$(basename "$rpm")
        local target_file="$target_dir/$base"

        # Copy to output dir if needed
        if [ "$target_dir" != "$rpm_dir" ] && [ ! -f "$target_file" ]; then
            cp "$rpm" "$target_file"
        fi

        log_info "Signing: $base"

        local sign_cmd=(rpmsign --addsign)
        if [ -n "${RPM_PASSPHRASE_FILE:-}" ] && [ -f "$RPM_PASSPHRASE_FILE" ]; then
            # Use passphrase file if available
            sign_cmd=(rpmsign --addsign --define "_signature gpg" --define "_gpg_name $key_id")
        fi

        if [ -n "${GPG_PASSPHRASE:-}" ]; then
            echo "$GPG_PASSPHRASE" | "${sign_cmd[@]}" \
                --define "__gpg_sign_cmd %{__gpg} gpg --batch --no-verbose --no-armor --pinentry-mode loopback --passphrase-fd 0 ${key_id:+-u $key_id} --no-secmem-warning -sbo %{__signature_filename} %{__plaintext_filename}" \
                "$target_file" 2>&1 && ((count++)) || ((failed++))
        else
            "${sign_cmd[@]}" "$target_file" 2>&1 && ((count++)) || ((failed++))
        fi
    done

    # Restore original macros
    if [ -n "$macro_file" ] && [ -f "$macro_file.bak" ]; then
        mv "$macro_file.bak" "$macro_file"
    fi

    log_info "RPM signing complete: $count signed, $failed failed"
    [ "$failed" -eq 0 ] || return 1
}

# ── Export public key ─────────────────────────────────────────────────────────
export_public_key() {
    local output_file="${1:-opentenbase-gpg-key.asc}"
    local key_id="${2:-}"

    log_step "Exporting public key..."

    local gpg_args=(--batch --yes --armor --export)
    if [ -n "$key_id" ]; then
        gpg_args+=("$key_id")
    fi

    gpg "${gpg_args[@]}" > "$output_file" 2>/dev/null

    if [ -s "$output_file" ]; then
        log_info "Public key exported to: $output_file"
        log_info "Key fingerprint:"
        gpg --with-fingerprint "$output_file" 2>/dev/null | grep -E '(pub|uid|fingerprint|Key fingerprint)' || true
    else
        log_error "Failed to export public key (empty output)"
        rm -f "$output_file"
        return 1
    fi
}

# ── Verify DEB signatures ────────────────────────────────────────────────────
verify_debs() {
    local deb_dir="$1"

    if [ ! -d "$deb_dir" ]; then
        log_error "DEB directory does not exist: $deb_dir"
        return 1
    fi

    log_step "Verifying DEB signatures in $deb_dir..."

    local success=0
    local fail=0

    for deb in "$deb_dir"/*.deb; do
        [ -f "$deb" ] || continue
        local base
        base=$(basename "$deb")
        local sig_file="$deb.sig"

        echo -n "  $base: "

        # Try dpkg-sig verify first
        if command -v dpkg-sig &>/dev/null; then
            if dpkg-sig --verify "$deb" &>/dev/null; then
                echo -e "${GREEN}VALID (dpkg-sig)${NC}"
                ((success++))
                continue
            fi
        fi

        # Try detached signature
        if [ -f "$sig_file" ]; then
            if gpg --batch --verify "$sig_file" "$deb" &>/dev/null; then
                echo -e "${GREEN}VALID (detached sig)${NC}"
                ((success++))
                continue
            fi
        fi

        echo -e "${RED}NO VALID SIGNATURE${NC}"
        ((fail++))
    done

    echo ""
    echo "Results: $success valid, $fail unsigned/invalid"
    [ "$fail" -eq 0 ] || return 1
}

# ── Verify RPM signatures ────────────────────────────────────────────────────
verify_rpms() {
    local rpm_dir="$1"

    if [ ! -d "$rpm_dir" ]; then
        log_error "RPM directory does not exist: $rpm_dir"
        return 1
    fi

    log_step "Verifying RPM signatures in $rpm_dir..."

    install_signing_tools_rpm

    local success=0
    local fail=0

    for rpm in "$rpm_dir"/*.rpm; do
        [ -f "$rpm" ] || continue
        local base
        base=$(basename "$rpm")

        echo -n "  $base: "

        if rpm --checksig "$rpm" 2>&1 | grep -qE '(PGP|gpg|md5 OK|sha1 OK)'; then
            echo -e "${GREEN}VALID${NC}"
            ((success++))
        else
            echo -e "${RED}NO VALID SIGNATURE${NC}"
            ((fail++))
        fi
    done

    echo ""
    echo "Results: $success valid, $fail unsigned/invalid"
    [ "$fail" -eq 0 ] || return 1
}

# ── Generate GPG key ─────────────────────────────────────────────────────────
generate_gpg_key() {
    log_step "Generating GPG key pair..."

    echo ""
    echo "Choose key type:"
    echo "  1) RSA 4096-bit (recommended for compatibility)"
    echo "  2) Ed25519 (modern, smaller)"
    read -rp "Selection [1]: " key_type_choice

    local key_type="RSA"
    local key_length="4096"
    if [ "${key_type_choice:-1}" = "2" ]; then
        key_type="Ed25519"
        key_length=""
    fi

    read -rp "Name: " name
    read -rp "Email: " email
    read -rp "Comment (optional): " comment

    echo ""
    log_info "Generating key (follow the prompts)..."

    if [ "$key_type" = "Ed25519" ]; then
        gpg --full-generate-key --expert <<EOF
Key-Type: eddsa
Key-Curve: ed25519
Name-Real: $name
Name-Email: $email
Name-Comment: $comment
Expire-Date: 0
%commit
EOF
    else
        gpg --full-generate-key <<EOF
Key-Type: RSA
Key-Length: $key_length
Name-Real: $name
Name-Email: $email
Name-Comment: $comment
Expire-Date: 0
%commit
EOF
    fi

    log_info "Key generated:"
    gpg --list-keys --keyid-format long "$email"
    echo ""
    log_info "To export for CI, run:"
    echo "  gpg --armor --export-secret-keys '$email' | base64 -w0   # or just cat the ASCII armor"
    echo "  # Set this as GPG_PRIVATE_KEY in GitHub repository secrets"
}

# ── List GPG keys ────────────────────────────────────────────────────────────
list_gpg_keys() {
    log_step "GPG keys in keyring..."

    echo ""
    echo "=== Public Keys ==="
    gpg --list-keys --keyid-format long 2>/dev/null || echo "(none)"

    echo ""
    echo "=== Secret Keys ==="
    gpg --list-secret-keys --keyid-format long 2>/dev/null || echo "(none)"
}

# ── Cleanup ──────────────────────────────────────────────────────────────────
cleanup_gpg_home() {
    if [ -n "${GNUPGHOME:-}" ] && [[ "$GNUPGHOME" == /tmp/opentenbase-gpg-* ]]; then
        rm -rf "$GNUPGHOME"
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
    local ci_mode=false
    local generate=false
    local list_keys=false
    local key_id=""
    local deb_dir=""
    local rpm_dir=""
    local output_dir=""
    local export_file=""
    local verify_deb_dir=""
    local verify_rpm_dir=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --ci)             ci_mode=true; shift ;;
            --generate)       generate=true; shift ;;
            --list)           list_keys=true; shift ;;
            -k|--key)         key_id="$2"; shift 2 ;;
            --deb-dir)        deb_dir="$2"; shift 2 ;;
            --rpm-dir)        rpm_dir="$2"; shift 2 ;;
            --output-dir)     output_dir="$2"; shift 2 ;;
            --export)         export_file="$2"; shift 2 ;;
            --import)         ci_mode=true; shift ;;  # alias
            --verify-deb)     verify_deb_dir="$2"; shift 2 ;;
            --verify-rpm)     verify_rpm_dir="$2"; shift 2 ;;
            -h|--help)        show_help; exit 0 ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Ensure cleanup on exit
    trap cleanup_gpg_home EXIT

    echo "========================================"
    echo " OpenTenBase GPG Package Signing"
    echo "========================================"
    echo ""

    # ── Generate mode ──
    if [ "$generate" = true ]; then
        generate_gpg_key
        exit 0
    fi

    # ── List mode ──
    if [ "$list_keys" = true ]; then
        list_gpg_keys
        exit 0
    fi

    # ── CI mode: import key from env ──
    if [ "$ci_mode" = true ]; then
        setup_gpg_from_env
        key_id="${GPG_KEY_ID:-$key_id}"

        # If only --import was requested (no signing dirs), export and exit
        if [ -z "$deb_dir" ] && [ -z "$rpm_dir" ] && [ -z "$export_file" ]; then
            log_info "Key imported successfully: $key_id"
            export_public_key "opentenbase-gpg-key.asc" "$key_id"
            exit 0
        fi
    fi

    # ── Export public key ──
    if [ -n "$export_file" ]; then
        export_public_key "$export_file" "$key_id"
        [ -z "$deb_dir" ] && [ -z "$rpm_dir" ] && exit 0
    fi

    # ── Signing ──
    local has_errors=false

    if [ -n "$deb_dir" ]; then
        install_signing_tools_deb
        if ! sign_debs "$deb_dir" "$key_id" "$output_dir"; then
            has_errors=true
        fi
    fi

    if [ -n "$rpm_dir" ]; then
        if ! sign_rpms "$rpm_dir" "$key_id" "$output_dir"; then
            has_errors=true
        fi
    fi

    # ── Verification ──
    if [ -n "$verify_deb_dir" ]; then
        verify_debs "$verify_deb_dir" || true
    fi

    if [ -n "$verify_rpm_dir" ]; then
        verify_rpms "$verify_rpm_dir" || true
    fi

    # ── Summary ──
    echo ""
    if [ "$has_errors" = true ]; then
        log_error "Some signing operations failed"
        exit 1
    elif [ -n "$deb_dir" ] || [ -n "$rpm_dir" ]; then
        log_info "All packages signed successfully"
    else
        show_help
    fi
}

main "$@"
