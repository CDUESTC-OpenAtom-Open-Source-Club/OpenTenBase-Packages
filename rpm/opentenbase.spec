Name:           opentenbase
Version:        %{!?otb_version:5.0}%{?otb_version}
Release:        1
Summary:        OpenTenBase distributed database system
License:        BSD
URL:            https://github.com/OpenTenBase/OpenTenBase
Source0:        opentenbase-%{version}-%{_arch}.tar.gz
Source1:        opentenbase-ctl
Source2:        pg_hba.conf.template

%define otb_ver %{version}
%define otb_prefix /usr/lib/opentenbase/%{otb_ver}

# Disable Fedora's annotated/hardened/LTO build macros
# These inject -specs=...annobin-cc1, -flto=auto, etc. into CFLAGS/LDFLAGS
%undefine _annotated_build
%undefine _hardened_build
%undefine _lto_cflags

# Filter out GLIBC_PRIVATE dependency (false positive from RPM auto-detection)
%global __requires_exclude ^libc\\.so\\.6\\(GLIBC_PRIVATE\\)

BuildRequires:  gcc gcc-c++ make bison flex perl
BuildRequires:  readline-devel zlib-devel openssl-devel pam-devel
BuildRequires:  libxml2-devel openldap-devel libuuid-devel
BuildRequires:  libcurl-devel lz4-devel
BuildRequires:  pkg-config libtool

# Optional: may not be available in all repos (CRB/PowerTools)
# BuildRequires:  zstd-devel libssh2-devel

Requires:       openssl-libs readline zlib libxml2 openldap libuuid libcurl lz4-libs

%description
OpenTenBase is an advanced enterprise-level database management system
based on PostgreSQL. It supports distributed transactions, parallel
computing, security, management, and audit functions.

%prep
%setup -q -c -n opentenbase

%build
# Find the source directory (could be OpenTenBase, OpenTenBase-main, etc.)
SRCDIR=$(find . -maxdepth 1 -type d -name 'OpenTenBase*' -o -name 'opentenbase*' | head -1)
if [ -z "$SRCDIR" ]; then
    # Maybe the content is directly in the current directory
    if [ -f configure ]; then
        SRCDIR="."
    else
        echo "ERROR: Cannot find source directory"
        exit 1
    fi
fi
cd "$SRCDIR"

# GCC compatibility patches
if grep -q 'typedef char bool;' src/include/c.h 2>/dev/null; then
    sed -i 's/typedef char bool;/typedef _Bool bool;/' src/include/c.h
fi
if grep -q 'false, false, NULL' src/gtm/main/gtm_opt.c 2>/dev/null; then
    sed -i '/enable_gtm_resqueue_debug/,/},/{s/true, false, NULL/true, NULL, NULL, false, NULL/; s/false, false, NULL/false, NULL, NULL, false, NULL/}' src/gtm/main/gtm_opt.c
fi

# Patch configure to use dynamic linking instead of hardcoded /usr/local/lib paths
sed -i 's|/usr/local/lib/liblz4.a|-llz4|g' configure

# Fix ldap_r deprecation: newer OpenLDAP merged ldap_r into ldap
# Always patch - ldap is backwards compatible with ldap_r
sed -i 's/-lldap_r/-lldap/g' configure
echo "NOTE: patched configure to use -lldap instead of -lldap_r"

# Check for real zstd-devel and provide comprehensive stub if missing
# OpenTenBase unconditionally compiles zstd_compress.c and gtm_store.c
# which include zstd.h, so we must provide types even without the real library
ZSTD_FOUND=0
if [ -f /usr/include/zstd.h ] && { [ -f /usr/lib64/libzstd.so ] || [ -f /usr/lib/libzstd.so ]; }; then
    ZSTD_FOUND=1
fi

if [ "$ZSTD_FOUND" = "0" ]; then
    echo "NOTE: zstd-devel not found, installing comprehensive stub zstd.h"
    mkdir -p /usr/include
    cat > /usr/include/zstd.h << 'ZSTD_STUB'
/* Comprehensive stub zstd.h for builds without zstd-devel */
#ifndef ZSTD_H_STUB
#define ZSTD_H_STUB
#include <stddef.h>

/* Version */
#define ZSTD_VERSION_MAJOR 1
#define ZSTD_VERSION_MINOR 5
#define ZSTD_VERSION_RELEASE 0

/* Compression levels */
#define ZSTD_CLEVEL_DEFAULT 3

/* Strategy */
typedef enum {
    ZSTD_fast=1, ZSTD_dfast=2, ZSTD_greedy=3, ZSTD_lazy=4,
    ZSTD_lazy2=5, ZSTD_btlazy2=6, ZSTD_btopt=7, ZSTD_btultra=8,
    ZSTD_btultra2=9
} ZSTD_strategy;

/* Reset directive */
typedef enum {
    ZSTD_reset_session_only=1,
    ZSTD_reset_parameters=2,
    ZSTD_reset_session_and_parameters=3
} ZSTD_ResetDirective;

/* End directive */
typedef enum { ZSTD_e_continue=0, ZSTD_e_end=1, ZSTD_e_flush=2 } ZSTD_EndDirective;

/* Buffer types */
typedef struct {
    const void* src;
    size_t size;
    size_t pos;
} ZSTD_inBuffer;

typedef struct {
    void* dst;
    size_t size;
    size_t pos;
} ZSTD_outBuffer;

/* Opaque context types */
typedef struct ZSTD_CCtx_s ZSTD_CCtx;
typedef struct ZSTD_DCtx_s ZSTD_DCtx;
typedef struct ZSTD_CDict_s ZSTD_CDict;
typedef struct ZSTD_DDict_s ZSTD_DDict;

/* CStream/DStream aliases */
typedef ZSTD_CCtx ZSTD_CStream;
typedef ZSTD_DCtx ZSTD_DStream;

/* Compression parameter */
typedef enum {
    ZSTD_c_compressionLevel=100,
    ZSTD_c_windowLog=101,
    ZSTD_c_hashLog=102,
    ZSTD_c_chainLog=103,
    ZSTD_c_searchLog=104,
    ZSTD_c_minMatch=105,
    ZSTD_c_targetLength=106,
    ZSTD_c_strategy=107,
    ZSTD_c_enableLongDistanceMatching=160,
    ZSTD_c_ldmHashLog=161,
    ZSTD_c_ldmMinMatch=162,
    ZSTD_c_ldmBucketSizeLog=163,
    ZSTD_c_ldmHashRateLog=164,
    ZSTD_c_contentSizeFlag=200,
    ZSTD_c_checksumFlag=201,
    ZSTD_c_dictIDFlag=202,
    ZSTD_c_nbWorkers=400,
    ZSTD_c_jobSize=401,
    ZSTD_c_overlapLog=402
} ZSTD_cParameter;

/* Decompression parameter */
typedef enum {
    ZSTD_d_windowLogMax=100
} ZSTD_dParameter;

/* Error code type */
typedef size_t ZSTD_ErrorCode;

/* Macros */
#define ZSTD_BLOCKSIZE_MAX (128 * 1024)

/* Simple API */
static inline size_t ZSTD_compress(void* dst, size_t dstCapacity,
    const void* src, size_t srcSize, int compressionLevel) {
    (void)dst; (void)dstCapacity; (void)src; (void)srcSize; (void)compressionLevel;
    return (size_t)-1;
}
static inline size_t ZSTD_decompress(void* dst, size_t dstCapacity,
    const void* src, size_t compressedSize) {
    (void)dst; (void)dstCapacity; (void)src; (void)compressedSize;
    return (size_t)-1;
}
static inline unsigned long long ZSTD_getFrameContentSize(const void* src, size_t srcSize) {
    (void)src; (void)srcSize; return 0;
}
static inline size_t ZSTD_compressBound(size_t srcSize) { (void)srcSize; return srcSize + (srcSize >> 8) + 64; }
static inline unsigned ZSTD_isError(size_t code) { return code > (size_t)-128; }
static inline const char* ZSTD_getErrorName(size_t code) { (void)code; return "zstd stub: not available"; }
static inline int ZSTD_maxCLevel(void) { return 19; }
static inline unsigned ZSTD_versionNumber(void) { return 10500; }

/* CCtx API */
static inline ZSTD_CCtx* ZSTD_createCCtx(void) { return (ZSTD_CCtx*)0; }
static inline size_t ZSTD_freeCCtx(ZSTD_CCtx* cctx) { (void)cctx; return 0; }
static inline size_t ZSTD_compressCCtx(ZSTD_CCtx* cctx, void* dst, size_t dstCap,
    const void* src, size_t srcSize, int level) {
    (void)cctx; (void)dst; (void)dstCap; (void)src; (void)srcSize; (void)level;
    return (size_t)-1;
}
static inline size_t ZSTD_compress2(ZSTD_CCtx* cctx, void* dst, size_t dstCap,
    const void* src, size_t srcSize) {
    (void)cctx; (void)dst; (void)dstCap; (void)src; (void)srcSize;
    return (size_t)-1;
}

/* DCtx API */
static inline ZSTD_DCtx* ZSTD_createDCtx(void) { return (ZSTD_DCtx*)0; }
static inline size_t ZSTD_freeDCtx(ZSTD_DCtx* dctx) { (void)dctx; return 0; }
static inline size_t ZSTD_decompressDCtx(ZSTD_DCtx* dctx, void* dst, size_t dstCap,
    const void* src, size_t srcSize) {
    (void)dctx; (void)dst; (void)dstCap; (void)src; (void)srcSize;
    return (size_t)-1;
}

/* CCtx advanced API */
static inline size_t ZSTD_CCtx_setParameter(ZSTD_CCtx* cctx, ZSTD_cParameter param, int value) {
    (void)cctx; (void)param; (void)value; return 0;
}
static inline size_t ZSTD_CCtx_setPledgedSrcSize(ZSTD_CCtx* cctx, unsigned long long pledgedSrcSize) {
    (void)cctx; (void)pledgedSrcSize; return 0;
}
static inline size_t ZSTD_CCtx_loadDictionary(ZSTD_CCtx* cctx, const void* dict, size_t dictSize) {
    (void)cctx; (void)dict; (void)dictSize; return 0;
}
static inline size_t ZSTD_CCtx_reset(ZSTD_CCtx* cctx, ZSTD_ResetDirective reset) {
    (void)cctx; (void)reset; return 0;
}

/* DCtx advanced API */
static inline size_t ZSTD_DCtx_setParameter(ZSTD_DCtx* dctx, ZSTD_dParameter param, int value) {
    (void)dctx; (void)param; (void)value; return 0;
}
static inline size_t ZSTD_DCtx_loadDictionary(ZSTD_DCtx* dctx, const void* dict, size_t dictSize) {
    (void)dctx; (void)dict; (void)dictSize; return 0;
}
static inline size_t ZSTD_DCtx_reset(ZSTD_DCtx* dctx, ZSTD_ResetDirective reset) {
    (void)dctx; (void)reset; return 0;
}

/* Streaming compression API */
static inline ZSTD_CStream* ZSTD_createCStream(void) { return (ZSTD_CStream*)0; }
static inline size_t ZSTD_freeCStream(ZSTD_CStream* zcs) { (void)zcs; return 0; }
static inline size_t ZSTD_initCStream(ZSTD_CStream* zcs, int compressionLevel) {
    (void)zcs; (void)compressionLevel; return 0;
}
static inline size_t ZSTD_compressStream(ZSTD_CStream* zcs, ZSTD_outBuffer* output, ZSTD_inBuffer* input) {
    (void)zcs; (void)output; (void)input; return (size_t)-1;
}
static inline size_t ZSTD_compressStream2(ZSTD_CCtx* cctx, ZSTD_outBuffer* output, ZSTD_inBuffer* input, ZSTD_EndDirective endOp) {
    (void)cctx; (void)output; (void)input; (void)endOp; return (size_t)-1;
}
static inline size_t ZSTD_flushStream(ZSTD_CStream* zcs, ZSTD_outBuffer* output) {
    (void)zcs; (void)output; return (size_t)-1;
}
static inline size_t ZSTD_endStream(ZSTD_CStream* zcs, ZSTD_outBuffer* output) {
    (void)zcs; (void)output; return (size_t)-1;
}
static inline size_t ZSTD_CStreamInSize(void) { return ZSTD_BLOCKSIZE_MAX; }
static inline size_t ZSTD_CStreamOutSize(void) { return ZSTD_compressBound(ZSTD_BLOCKSIZE_MAX); }

/* Streaming decompression API */
static inline ZSTD_DStream* ZSTD_createDStream(void) { return (ZSTD_DStream*)0; }
static inline size_t ZSTD_freeDStream(ZSTD_DStream* zds) { (void)zds; return 0; }
static inline size_t ZSTD_initDStream(ZSTD_DStream* zds) { (void)zds; return 0; }
static inline size_t ZSTD_decompressStream(ZSTD_DStream* zds, ZSTD_outBuffer* output, ZSTD_inBuffer* input) {
    (void)zds; (void)output; (void)input; return (size_t)-1;
}
static inline size_t ZSTD_DStreamInSize(void) { return ZSTD_BLOCKSIZE_MAX + 4; }
static inline size_t ZSTD_DStreamOutSize(void) { return ZSTD_BLOCKSIZE_MAX; }

/* CDict API */
static inline ZSTD_CDict* ZSTD_createCDict(const void* dictBuffer, size_t dictSize, int compressionLevel) {
    (void)dictBuffer; (void)dictSize; (void)compressionLevel; return (ZSTD_CDict*)0;
}
static inline size_t ZSTD_freeCDict(ZSTD_CDict* cdict) { (void)cdict; return 0; }

/* DDict API */
static inline ZSTD_DDict* ZSTD_createDDict(const void* dictBuffer, size_t dictSize) {
    (void)dictBuffer; (void)dictSize; return (ZSTD_DDict*)0;
}
static inline size_t ZSTD_freeDDict(ZSTD_DDict* ddict) { (void)ddict; return 0; }

#endif /* ZSTD_H_STUB */
ZSTD_STUB
fi

# Architecture flags
CFLAGS="-O2 -g -DNOLIC -Wno-error=incompatible-pointer-types -Wno-error=implicit-function-declaration -Wno-error=int-conversion -Wno-incompatible-pointer-types"
%ifarch x86_64
CFLAGS="$CFLAGS -msse4.2 -mcrc32"
%endif
%ifarch aarch64
CFLAGS="$CFLAGS -march=armv8-a"
%endif
export CFLAGS
# Set LDFLAGS cleanly (RPM macros are sanitized by %undefine above)
export LDFLAGS="-Wl,-rpath,%{otb_prefix}/lib"

# Add -latomic on Fedora (needed for 128-bit atomics: __sync_val_compare_and_swap_16)
if [ -f /etc/fedora-release ]; then
    export LIBS="$LIBS -latomic"
    echo "NOTE: Fedora detected, adding -latomic to LIBS"
fi

# Debug: test compiler before configure
echo "=== Compiler test ==="
echo 'int main() { return 0; }' > /tmp/otb_test.c
if gcc -o /tmp/otb_test /tmp/otb_test.c $CFLAGS $LDFLAGS 2>&1; then
    echo "NOTE: compiler test PASSED"
else
    echo "NOTE: compiler test FAILED with CFLAGS=$CFLAGS LDFLAGS=$LDFLAGS"
    # Try without our flags
    gcc -o /tmp/otb_test /tmp/otb_test.c 2>&1 && echo "NOTE: compiler works without custom flags"
fi
rm -f /tmp/otb_test /tmp/otb_test.c

CONFIGURE_OPTS="--prefix=%{otb_prefix} \
    --sysconfdir=/etc/opentenbase/%{otb_ver} \
    --datadir=%{otb_prefix}/share \
    --libdir=%{otb_prefix}/lib \
    --includedir=%{otb_prefix}/include \
    --enable-license=no \
    --enable-user-switch \
    --with-openssl \
    --with-uuid=e2fs \
    --with-pam \
    --with-ldap \
    --with-libxml \
    --with-lz4"

# Only enable zstd if real zstd-devel is installed (not stub)
if [ "$ZSTD_FOUND" = "1" ]; then
    # Patch configure to use dynamic linking for zstd
    sed -i 's|/usr/local/lib/libzstd.a|-lzstd|g' configure
    CONFIGURE_OPTS="$CONFIGURE_OPTS --with-zstd"
    echo "NOTE: zstd-devel found, building with zstd support"
else
    CONFIGURE_OPTS="$CONFIGURE_OPTS --without-zstd"
    echo "NOTE: zstd-devel not found, building without zstd support (stub header installed)"
fi

# Clear CPPFLAGS to avoid RPM-injected preprocessor flags
export CPPFLAGS=""
# Pass CFLAGS/LDFLAGS/LIBS as configure arguments (highest priority in autoconf)
./configure $CONFIGURE_OPTS CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" LIBS="$LIBS" || {
    echo "=== CONFIGURE FAILED ==="
    echo "CFLAGS=$CFLAGS"
    echo "LDFLAGS=$LDFLAGS"
    echo "LIBS=$LIBS"
    echo "CPPFLAGS=$CPPFLAGS"
    if [ -f config.log ]; then
        echo "=== Last 50 lines of config.log ==="
        tail -50 config.log
    fi
    exit 1
}

# If zstd-devel is not available, remove -lzstd from linker flags
# (configure may still add it even with --without-zstd due to stub header)
if [ "$ZSTD_FOUND" = "0" ]; then
    grep -rl -- '-lzstd' . 2>/dev/null | xargs sed -i 's/-lzstd//g' 2>/dev/null || true
    echo "NOTE: removed -lzstd from linker flags (using stub zstd.h)"
fi

# If libssh2-devel is not available, skip opentenbase_ctl (uses libssh2 functions)
# Check for actual shared library, not just headers
LIBSSH2_FOUND=0
if { [ -f /usr/lib64/libssh2.so ] || [ -f /usr/lib/libssh2.so ]; }; then
    LIBSSH2_FOUND=1
fi

# Pre-build libpq and generate objfiles.txt (race condition fix)
# libpq's Makefile has 'all: all-lib' but doesn't generate objfiles.txt
# which the postgres binary needs to link against libpq objects
make -j$(nproc) -C src/interfaces/libpq
( cd src/interfaces/libpq && for f in *.o; do echo "src/interfaces/libpq/$f"; done ) > src/interfaces/libpq/objfiles.txt

make -j$(nproc)

# Build contrib, but skip uuid-ossp (requires OSSP UUID not available on RPM distros)
sed -i 's/^SUBDIRS += uuid-ossp/# SUBDIRS += uuid-ossp/' contrib/Makefile
sed -i 's/^ALWAYS_SUBDIRS += uuid-ossp/# ALWAYS_SUBDIRS += uuid-ossp/' contrib/Makefile

# Skip opentenbase_ctl if libssh2 is not available (it requires libssh2 for SSH functionality)
if [ "$LIBSSH2_FOUND" = "0" ]; then
    # opentenbase_ctl is the last entry in the SUBDIRS continuation list in contrib/Makefile
    # Remove trailing backslash from previous entry first, then delete the line
    sed -i '/opentenbase_ai/s/ *\\$//' contrib/Makefile
    sed -i '/opentenbase_ctl/d' contrib/Makefile
    echo "NOTE: libssh2-devel not found, skipping opentenbase_ctl"
fi

make -C contrib -j$(nproc)

%install
SRCDIR=$(find . -maxdepth 1 -type d -name 'OpenTenBase*' -o -name 'opentenbase*' | head -1)
if [ -z "$SRCDIR" ]; then
    if [ -f Makefile ]; then
        SRCDIR="."
    else
        echo "ERROR: Cannot find source directory in install"
        exit 1
    fi
fi
cd "$SRCDIR"

make DESTDIR=%{buildroot} install
make DESTDIR=%{buildroot} -C contrib install

# Create symlinks in /usr/bin
mkdir -p %{buildroot}/usr/bin
for f in %{buildroot}%{otb_prefix}/bin/*; do
    bname=$(basename "$f")
    ln -s %{otb_prefix}/bin/"$bname" %{buildroot}/usr/bin/"$bname"
done

# Install opentenbase-ctl management script
install -m 755 %{SOURCE1} %{buildroot}/usr/bin/opentenbase-ctl

# Install pg_hba.conf template
mkdir -p %{buildroot}/etc/opentenbase/%{otb_ver}
install -m 644 %{SOURCE2} %{buildroot}/etc/opentenbase/%{otb_ver}/pg_hba.conf.template

# Install switch-version script
cat > %{buildroot}/usr/bin/opentenbase-switch-version << 'SWITCHSCRIPT'
#!/bin/bash
# opentenbase-switch-version — switch between installed OpenTenBase versions
set -e
CONF_DIR="/etc/opentenbase"
CURRENT_LINK="$CONF_DIR/current"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
check_root() { [ "$(id -u)" -eq 0 ] || { log_error "must run as root"; exit 1; }; }
list_versions() {
    local versions=()
    for dir in "$CONF_DIR"/*/; do
        [ -d "$dir" ] || continue
        local ver=$(basename "$dir")
        [ "$ver" = "current" ] && continue
        [ -f "$dir/opentenbase.conf" ] && versions+=("$ver")
    done
    echo "${versions[@]}"
}
get_current() {
    [ -L "$CURRENT_LINK" ] && basename "$(readlink -f "$CURRENT_LINK")" || echo ""
}
show_version_info() {
    local ver="$1" current=$(get_current) marker=""
    [ "$ver" = "$current" ] && marker=" ${GREEN}(active)${NC}"
    local home="" port=""
    [ -f "$CONF_DIR/$ver/opentenbase.conf" ] && {
        home=$(grep '^OTB_HOME=' "$CONF_DIR/$ver/opentenbase.conf" | cut -d'"' -f2)
        port=$(grep '^COORD_PORT=' "$CONF_DIR/$ver/opentenbase.conf" | cut -d= -f2 | tr -d ' ')
    }
    echo -e "  $ver${marker}"
    [ -n "$home" ] && echo "    prefix: $home"
    [ -n "$port" ] && echo "    coord port: $port"
}
cmd_list() {
    local versions=$(list_versions)
    [ -z "$versions" ] && { log_warn "No OpenTenBase versions found in $CONF_DIR"; exit 0; }
    echo "Installed OpenTenBase versions:"
    echo ""
    for ver in $versions; do show_version_info "$ver"; done
    echo ""
    local current=$(get_current)
    [ -n "$current" ] && log_info "Active version: $current" || log_warn "No active version set"
}
cmd_switch() {
    local target="$1"
    [ ! -d "$CONF_DIR/$target" ] && { log_error "Version $target not found"; exit 1; }
    [ ! -f "$CONF_DIR/$target/opentenbase.conf" ] && { log_error "No config for version $target"; exit 1; }
    local current=$(get_current)
    [ "$target" = "$current" ] && { log_info "Already on version $target"; return 0; }
    if pgrep -x postgres >/dev/null 2>&1 || pgrep -x gtm >/dev/null 2>&1; then
        log_warn "OpenTenBase server processes are running."
        echo "  opentenbase-ctl stop"
        echo ""
        read -p "Continue anyway? [y/N] " -n 1 -r; echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi
    ln -sfn "$CONF_DIR/$target" "$CURRENT_LINK"
    log_info "Switched to OpenTenBase $target"
    echo "Active config: $CONF_DIR/current/opentenbase.conf"
    local port=$(grep '^COORD_PORT=' "$CONF_DIR/$target/opentenbase.conf" | cut -d= -f2 | tr -d ' ')
    [ -n "$port" ] && echo "Coordinator port: $port"
    echo ""
    echo "To initialize and start:"
    echo "  opentenbase-ctl init"
    echo "  opentenbase-ctl start"
}
case "${1:-}" in
    -h|--help) echo "Usage: opentenbase-switch-version [version]"; cmd_list ;;
    "") cmd_list ;;
    *) check_root; cmd_switch "$1" ;;
esac
SWITCHSCRIPT
chmod 755 %{buildroot}/usr/bin/opentenbase-switch-version

# ldconfig config
mkdir -p %{buildroot}/etc/ld.so.conf.d
echo '%{otb_prefix}/lib' > %{buildroot}/etc/ld.so.conf.d/opentenbase.conf

# Versioned directories
mkdir -p %{buildroot}/etc/opentenbase/%{otb_ver}
mkdir -p %{buildroot}/var/lib/opentenbase/%{otb_ver}
mkdir -p %{buildroot}/var/log/opentenbase/%{otb_ver}
mkdir -p %{buildroot}/var/run/opentenbase

# Version marker
echo "%{otb_ver}" > %{buildroot}%{otb_prefix}/VERSION

# Generate config
cat > %{buildroot}/etc/opentenbase/%{otb_ver}/opentenbase.conf <<CONF
ENABLED_NODES="gtm dn1 coord"
OTB_USER="opentenbase"
OTB_GROUP="opentenbase"
OTB_HOME="%{otb_prefix}"
GTM_PGDATA="/var/lib/opentenbase/%{otb_ver}/gtm"
GTM_PORT=6666
GTM_LOG="/var/log/opentenbase/%{otb_ver}/gtm.log"
COORD_PGDATA="/var/lib/opentenbase/%{otb_ver}/coord"
COORD_PORT=5432
COORD_NODENAME="coord1"
COORD_LOG="/var/log/opentenbase/%{otb_ver}/coord.log"
DN1_PGDATA="/var/lib/opentenbase/%{otb_ver}/dn1"
DN1_PORT=15432
DN1_NODENAME="dn001"
DN1_LOG="/var/log/opentenbase/%{otb_ver}/dn1.log"
COORD_FORWARD_PORT=6669
DN1_FORWARD_PORT=6670
COORD_POOLER_PORT=6667
DN1_POOLER_PORT=6668
START_ORDER="gtm coord dn1"
STOP_ORDER="coord dn1 gtm"
CONF

%files
%{otb_prefix}
/usr/bin/*
/etc/ld.so.conf.d/opentenbase.conf
%dir /etc/opentenbase/%{otb_ver}
%dir /var/lib/opentenbase/%{otb_ver}
%dir /var/log/opentenbase/%{otb_ver}
%dir /var/run/opentenbase
%config(noreplace) /etc/opentenbase/%{otb_ver}/opentenbase.conf
/etc/opentenbase/%{otb_ver}/pg_hba.conf.template

%post
ldconfig
if [ ! -L /etc/opentenbase/current ]; then
    ln -sf /etc/opentenbase/%{otb_ver} /etc/opentenbase/current
fi
if ! getent group opentenbase >/dev/null 2>&1; then
    groupadd --system opentenbase 2>/dev/null || true
fi
if ! getent passwd opentenbase >/dev/null 2>&1; then
    useradd --system --gid opentenbase --home-dir /var/lib/opentenbase \
        --shell /bin/bash --comment "OpenTenBase administrator" opentenbase 2>/dev/null || true
fi
chown opentenbase:opentenbase /var/lib/opentenbase/%{otb_ver}
chown opentenbase:opentenbase /var/log/opentenbase/%{otb_ver}
chown opentenbase:opentenbase /var/run/opentenbase

%postun
ldconfig
