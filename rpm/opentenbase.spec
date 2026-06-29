Name:           opentenbase
Version:        %{!?otb_version:5.0}%{?otb_version}
Release:        1
Summary:        OpenTenBase distributed database system
License:        BSD
URL:            https://github.com/OpenTenBase/OpenTenBase
Source0:        opentenbase-%{version}-%{_arch}.tar.gz
Source1:        pg_hba.conf.template
Source2:        opentenbase-psql

%define otb_ver %{version}
%define otb_prefix /usr/lib/opentenbase/%{otb_ver}
%define debug_package %{nil}

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
BuildRequires:  libssh2-devel pkg-config libtool
# opentenbase_ctl also needs CLI11, indicators (header-only, auto-installed in %build)
# and libpqxx (auto-built from source in %build if not in repos)

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

# Clear all RPM-injected compiler flags from environment
unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS

# Suppress all warnings (OpenTenBase code is not warning-clean on modern GCC)
# Use -DNOLIC to bypass license check, -msse4.2 -mcrc32 for x86_64
CFLAGS="-O2 -g -fPIC -w -Wno-error=incompatible-pointer-types -Wno-error=int-conversion -Wno-error=implicit-function-declaration -Wno-error=implicit-int -DNOLIC"
%ifarch x86_64
CFLAGS="$CFLAGS -mcx16 -msse4.2 -mcrc32"
%endif
%ifarch aarch64
CFLAGS="$CFLAGS -march=armv8-a"
%endif
export CFLAGS
# Set LDFLAGS cleanly (RPM macros are sanitized by %undefine above)
export LDFLAGS="-Wl,--allow-multiple-definition -Wl,-rpath,%{otb_prefix}/lib"

# Add -latomic (needed for 128-bit atomics: __sync_val_compare_and_swap_16)
# Ensure libatomic.so symlink exists (runtime package may only provide .so.1)
for dir in /usr/lib64 /usr/lib; do
    if [ -f "$dir/libatomic.so.1" ] && [ ! -f "$dir/libatomic.so" ]; then
        ln -s libatomic.so.1 "$dir/libatomic.so"
        echo "NOTE: created $dir/libatomic.so symlink"
    fi
done
# Use --no-as-needed to force link libatomic even with --as-needed in LDFLAGS
export LIBS="$LIBS -Wl,--no-as-needed -latomic -Wl,--as-needed"
echo "NOTE: added -latomic to LIBS"

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
    echo "CC=$CC"
    echo "GCC version: $(gcc --version 2>&1 | head -1)"
    # Try to reproduce the exact configure compiler test
    echo "=== Reproducing configure compiler test ==="
    echo 'int main() { return 0; }' > conftest.c
    echo "Test 1: gcc conftest.c \$CFLAGS \$LDFLAGS \$LIBS"
    gcc conftest.c $CFLAGS $LDFLAGS $LIBS 2>&1 || echo "FAILED"
    echo "Test 2: gcc conftest.c \$CFLAGS \$LDFLAGS"
    gcc conftest.c $CFLAGS $LDFLAGS 2>&1 || echo "FAILED"
    echo "Test 3: gcc conftest.c (no flags)"
    gcc conftest.c 2>&1 || echo "FAILED"
    rm -f conftest.c a.out
    if [ -f config.log ]; then
        echo "=== Compiler test section from config.log ==="
        grep -A 50 "checking whether the C compiler works" config.log | head -80
        echo "=== Full configure invocation from config.log ==="
        grep "^\$" config.log | head -10
    fi
    exit 1
}

# If zstd-devel is not available, remove -lzstd from linker flags
# (configure may still add it even with --without-zstd due to stub header)
if [ "$ZSTD_FOUND" = "0" ]; then
    grep -rl -- '-lzstd' . 2>/dev/null | xargs sed -i 's/-lzstd//g' 2>/dev/null || true
    echo "NOTE: removed -lzstd from linker flags (using stub zstd.h)"
fi

# ============================================================
# opentenbase_ctl: MANDATORY build (no conditional skip)
# All deps are auto-installed; build FAILS if any are missing
# ============================================================

# 1. Verify libssh2 (should be installed via BuildRequires)
if [ ! -f /usr/lib64/libssh2.so ] && [ ! -f /usr/lib/libssh2.so ]; then
    echo "ERROR: libssh2 not found — opentenbase_ctl requires it. Install libssh2-devel."
    exit 1
fi

# 2. Install CLI11 single-header from GitHub if not present
if [ ! -f /usr/include/CLI/CLI.hpp ] && [ ! -f /usr/local/include/CLI/CLI.hpp ]; then
    echo "NOTE: CLI11 not found, installing single-header v2.4.2 from GitHub"
    mkdir -p /usr/local/include/CLI
    curl -fsSL https://github.com/CLIUtils/CLI11/releases/download/v2.4.2/CLI11.hpp \
        -o /usr/local/include/CLI/CLI.hpp || {
        echo "ERROR: Failed to download CLI11 — opentenbase_ctl cannot be built"
        exit 1
    }
    echo "NOTE: CLI11 single-header installed to /usr/local/include/CLI/CLI.hpp"
fi

# 3. Install indicators header-only library from GitHub if not present
if [ ! -d /usr/local/include/indicators ] && [ ! -d /usr/include/indicators ]; then
    echo "NOTE: indicators not found, installing from GitHub"
    cd /tmp && rm -rf indicators_src
    git clone --depth 1 https://github.com/p-ranav/indicators.git /tmp/indicators_src || {
        echo "ERROR: Failed to clone indicators — opentenbase_ctl cannot be built"
        exit 1
    }
    mkdir -p /usr/local/include/indicators
    cp -r /tmp/indicators_src/include/indicators/* /usr/local/include/indicators/
    # indicators.hpp may be at different locations in different versions
    cp /tmp/indicators_src/include/indicators.hpp /usr/local/include/ 2>/dev/null || true
    rm -rf /tmp/indicators_src
    echo "NOTE: indicators headers installed to /usr/local/include/indicators/"
fi

# 4. ALWAYS build libpqxx 7.9.2 from source — system/EPEL versions are incompatible
#    EPEL provides older libpqxx (7.6.x/7.7.x) with range.hxx bugs that break opentenbase_ctl
#    Remove any existing system packages and headers first, then build from source
OTB_SRCDIR_ABS="$(pwd)"
echo "NOTE: Force-building libpqxx 7.9.2 from source (overriding any system version)"
rpm -e libpqxx libpqxx-devel 2>/dev/null || true
rm -rf /usr/include/pqxx /usr/lib64/libpqxx.* /usr/lib/libpqxx.*
cd /tmp && rm -rf libpqxx-*
curl -fsSL https://github.com/jtv/libpqxx/archive/refs/tags/7.9.2.tar.gz -o /tmp/libpqxx.tar.gz || {
    echo "ERROR: Failed to download libpqxx — opentenbase_ctl cannot be built"
    exit 1
}
tar xzf /tmp/libpqxx.tar.gz -C /tmp
cd /tmp/libpqxx-7.9.2
cmake -B build -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_SHARED_LIBS=ON -DSKIP_BUILD_TEST=ON
cmake --build build -j$(nproc)
cmake --install build
cd /tmp && rm -rf libpqxx-*
rm -f /tmp/libpqxx.tar.gz
ldconfig
cd "$OTB_SRCDIR_ABS"
echo "NOTE: libpqxx 7.9.2 force-built and installed (overrode system version)"

# Pre-build libpq and generate objfiles.txt (race condition fix)
# libpq's Makefile has 'all: all-lib' but doesn't generate objfiles.txt
# which the postgres binary needs to link against libpq objects
make -j$(nproc) -C src/interfaces/libpq
# Regenerate objfiles.txt after all objects are compiled (including conditional SSL objects)
# The parallel make may compile fe-secure-openssl.o after the initial glob
make -j$(nproc) -C src/interfaces/libpq  # ensure all objects compiled
( cd src/interfaces/libpq && for f in *.o; do echo "src/interfaces/libpq/$f"; done ) > src/interfaces/libpq/objfiles.txt
# Verify SSL objects are included
grep -q 'fe-secure-openssl' src/interfaces/libpq/objfiles.txt || {
    echo "WARNING: fe-secure-openssl.o missing from objfiles.txt, adding manually"
    echo "src/interfaces/libpq/fe-secure-openssl.o" >> src/interfaces/libpq/objfiles.txt
    echo "src/interfaces/libpq/sha2_openssl.o" >> src/interfaces/libpq/objfiles.txt
}

# Fix flex lex.backup race: replace the wc -l check + rm with simple rm -f
# The original recipe fails when parallel flex removes lex.backup before wc reads it
sed -i 's/if \[ `wc -l <lex\.backup` -eq 1 \]; then rm lex\.backup; else echo "Scanner requires backup; see lex\.backup\." 1>\&2; exit 1; fi/rm -f lex.backup/' src/Makefile.global

make -j$(nproc)

# Build contrib, but skip uuid-ossp (requires OSSP UUID not available on RPM distros)
sed -i 's/^SUBDIRS += uuid-ossp/# SUBDIRS += uuid-ossp/' contrib/Makefile
sed -i 's/^ALWAYS_SUBDIRS += uuid-ossp/# ALWAYS_SUBDIRS += uuid-ossp/' contrib/Makefile
# Skip pgsql-http on aarch64 (R_AARCH64_ADR_PREL_PG_HI21 relocation error)
%ifarch aarch64
sed -i '/pgsql-http/d' contrib/Makefile
%endif

# Skip opentenbase_ai and opentenbase_ctl for older versions (2.x) — not in upstream contrib/
# For v5.0: opentenbase_ctl is MANDATORY — all deps already installed above
if [ "$(cat /tmp/otb_version 2>/dev/null || echo '%{otb_ver}')" != "5.0" ]; then
    sed -i '/opentenbase_ai/s/ *\\$//' contrib/Makefile
    sed -i '/opentenbase_ctl/d' contrib/Makefile
    echo "NOTE: opentenbase_ctl not available in this version, skipping (v5.0+ only)"
fi

make -C contrib -j$(nproc)

# ============================================================
# POST-BUILD VERIFICATION: opentenbase_ctl MUST exist for v5.0
# ============================================================
if [ "$(cat /tmp/otb_version 2>/dev/null || echo '%{otb_ver}')" = "5.0" ]; then
    if [ ! -f contrib/opentenbase_ctl/opentenbase_ctl ]; then
        echo "============================================================"
        echo "FATAL: opentenbase_ctl binary not found after contrib build!"
        echo "Dependencies status:"
        echo "  CLI11: $(ls /usr/local/include/CLI/CLI.hpp /usr/include/CLI/CLI.hpp 2>/dev/null || echo MISSING)"
        echo "  indicators: $(ls -d /usr/local/include/indicators /usr/include/indicators 2>/dev/null || echo MISSING)"
        echo "  libpqxx: $(find /usr/include/pqxx/pqxx /usr/local/include/pqxx/pqxx 2>/dev/null || echo MISSING)"
        echo "  libssh2: $(ls /usr/lib64/libssh2.so /usr/lib/libssh2.so 2>/dev/null || echo MISSING)"
        echo "Attempting manual build for diagnostics..."
        cd contrib/opentenbase_ctl && make clean 2>/dev/null; make 2>&1 | tail -30
        echo "============================================================"
        exit 1
    fi
    echo "NOTE: opentenbase_ctl binary built successfully"
fi

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

# Bundle libpqxx.so into OpenTenBase lib dir (rpath already set to find it here)
for libpath in /usr/lib64/libpqxx.so /usr/lib/libpqxx.so /usr/local/lib/libpqxx.so; do
    if [ -f "$libpath" ]; then
        cp -L "$libpath" %{buildroot}%{otb_prefix}/lib/
        echo "Bundled $libpath into package"
        break
    fi
done

# Create symlinks in /usr/bin
mkdir -p %{buildroot}/usr/bin
for f in %{buildroot}%{otb_prefix}/bin/*; do
    bname=$(basename "$f")
    ln -s %{otb_prefix}/bin/"$bname" %{buildroot}/usr/bin/"$bname"
done

# Create opentenbase-ctl symlink → official opentenbase_ctl binary
ln -s %{otb_prefix}/bin/opentenbase_ctl %{buildroot}/usr/bin/opentenbase-ctl

# Install opentenbase-psql wrapper
install -m 755 %{SOURCE2} %{buildroot}/usr/bin/opentenbase-psql

# Install pg_hba.conf template
mkdir -p %{buildroot}/etc/opentenbase/%{otb_ver}
install -m 644 %{SOURCE1} %{buildroot}/etc/opentenbase/%{otb_ver}/pg_hba.conf.template

# Install opentenbase_ctl config template
cat > %{buildroot}/etc/opentenbase/%{otb_ver}/opentenbase_config.ini.example << 'INIEOF'
# OpenTenBase single-node local deployment config
# Usage: opentenbase_ctl install -c opentenbase_config.ini
#
# IMPORTANT: package MUST point to a .tar.gz file, NOT a directory!
# Create the tar.gz before running install:
#   cd /tmp && mkdir otb-pkg && cp -af %{otb_prefix}/* otb-pkg/
#   cd otb-pkg && tar -zcf /tmp/opentenbase-5.0.tar.gz *
# Or use: sudo bash scripts/deploy-opentenbase.sh --yes

[instance]
name=opentenbase01
type=distributed
package=/tmp/opentenbase-%{otb_ver}.tar.gz

[gtm]
master=127.0.0.1

[coordinators]
master=127.0.0.1
nodes-per-server=1

[datanodes]
master=127.0.0.1
nodes-per-server=1

[server]
ssh-user=opentenbase
ssh-port=22

[log]
level=INFO
INIEOF

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
        echo "  opentenbase_ctl stop
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
    echo "To install and start:"
    echo "  opentenbase_ctl install -c /tmp/otb_config.ini"
    echo "  opentenbase_ctl start
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
COORD_NODENAME="coord1"
DN1_NODENAME="dn1"
START_ORDER="gtm coord dn1"
STOP_ORDER="dn1 coord gtm"
GTM_HOST=127.0.0.1
GTM_PGDATA="/var/lib/opentenbase/%{otb_ver}/gtm"
GTM_PORT=6666
GTM_LOG="/var/log/opentenbase/%{otb_ver}/gtm.log"
COORD_HOST=127.0.0.1
COORD_PGDATA="/var/lib/opentenbase/%{otb_ver}/coord"
COORD_PORT=11003
COORD_POOLER_PORT=6667
COORD_FORWARD_PORT=6669
COORD_LOG="/var/log/opentenbase/%{otb_ver}/coord.log"
DN_HOST=127.0.0.1
DN1_PGDATA="/var/lib/opentenbase/%{otb_ver}/dn1"
DN1_PORT=15432
DN_PORT=15432
DN1_POOLER_PORT=6668
DN_POOLER_PORT=6668
DN1_FORWARD_PORT=6670
DN_FORWARD_PORT=6670
DN1_LOG="/var/log/opentenbase/%{otb_ver}/dn1.log"
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
/etc/opentenbase/%{otb_ver}/opentenbase_config.ini.example

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
