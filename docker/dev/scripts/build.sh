#!/bin/bash
# OpenTenBase full build script
# Runs configure + make + install + contrib
set -e

OTB_PREFIX="${OTB_PREFIX:-/usr/lib/opentenbase/5.0}"
SRC_DIR="${SRC_DIR:-/src/OpenTenBase}"

cd "$SRC_DIR"

# Base CFLAGS
# -DNOLIC: bypass license check (required for full functionality)
# -Wno-error=*: GCC 14+ compatibility for older C code
CFLAGS="-O2 -g -DNOLIC -Wno-error=incompatible-pointer-types -Wno-error=implicit-function-declaration -Wno-error=int-conversion -Wno-incompatible-pointer-types"

# Architecture-specific flags
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    CFLAGS="$CFLAGS -msse4.2 -mcrc32"
elif [ "$ARCH" = "aarch64" ]; then
    CFLAGS="$CFLAGS -march=armv8-a"
fi

export CFLAGS
export LDFLAGS="-Wl,-rpath,${OTB_PREFIX}/lib"

echo "=== OpenTenBase Build ==="
echo "Source:  $SRC_DIR"
echo "Prefix:  $OTB_PREFIX"
echo "Arch:    $ARCH"
echo "CFLAGS:  $CFLAGS"
echo "========================="

# Fix: GCC 12+ treats 'typedef char bool' and '_Bool' as conflicting types.
# Change c.h to use _Bool instead of char for bool typedef.
if grep -q 'typedef char bool;' src/include/c.h 2>/dev/null; then
    echo "Patching c.h: typedef char bool -> typedef _Bool bool"
    sed -i 's/typedef char bool;/typedef _Bool bool;/' src/include/c.h
fi

# Fix: gtm_opt.c has wrong number of struct initializer fields for enable_gtm_resqueue_debug.
# The entry has 3 fields (false, false, NULL) but should have 5 (false, NULL, NULL, false, NULL).
# This was masked by typedef char bool (char 0 implicitly converts to function pointer) but
# fails with typedef _Bool bool (_Bool cannot convert to function pointer).
if grep -q 'false, false, NULL' src/gtm/main/gtm_opt.c 2>/dev/null; then
    echo "Patching gtm_opt.c: fixing enable_gtm_resqueue_debug struct initializer"
    sed -i '/enable_gtm_resqueue_debug/,/},/{s/true, false, NULL/true, NULL, NULL, false, NULL/; s/false, false, NULL/false, NULL, NULL, false, NULL/}' src/gtm/main/gtm_opt.c
fi

# Apply sharding patch if it exists
if [ -f "02-nolic-sharding.patch" ]; then
    echo "Applying 02-nolic-sharding.patch..."
    patch -p1 < 02-nolic-sharding.patch || true
fi

# Workaround: OpenTenBase configure hardcodes /usr/local/lib/ paths for some libs
# Create symlinks if the libraries exist elsewhere
mkdir -p /usr/local/lib
for lib in libzstd.a liblz4.a; do
    if [ ! -f "/usr/local/lib/$lib" ]; then
        LIB_PATH=$(find /usr -name "$lib" 2>/dev/null | head -1)
        if [ -n "$LIB_PATH" ]; then
            echo "Creating symlink: /usr/local/lib/$lib -> $LIB_PATH"
            ln -sf "$LIB_PATH" "/usr/local/lib/$lib"
        fi
    fi
done

# Configure
echo "Running ./configure..."
./configure \
    --prefix="$OTB_PREFIX" \
    --sysconfdir=/etc/opentenbase \
    --datadir="$OTB_PREFIX/share" \
    --libdir="$OTB_PREFIX/lib" \
    --includedir="$OTB_PREFIX/include" \
    --enable-user-switch \
    --with-openssl \
    --with-ossp-uuid \
    --with-pam \
    --with-ldap \
    --with-libxml \
    --with-libcurl \
    --with-lz4 \
    --with-zstd

# Build
echo "Running make -j$(nproc)..."
make -j"$(nproc)"

# Install
echo "Running make install..."
make install

# Build and install contrib
echo "Building contrib..."
make -C contrib -j"$(nproc)"
echo "Installing contrib..."
make -C contrib install

echo "=== Build complete ==="
echo "Installed to: $OTB_PREFIX"
