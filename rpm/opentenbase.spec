Name:           opentenbase
Version:        %{!?otb_version:5.0}%{?otb_version}
Release:        1
Summary:        OpenTenBase distributed database system
License:        BSD
URL:            https://github.com/OpenTenBase/OpenTenBase
Source0:        opentenbase-%{version}-%{_arch}.tar.gz

%define otb_ver %{version}
%define otb_prefix /usr/lib/opentenbase/%{otb_ver}

# Filter out GLIBC_PRIVATE dependency (false positive from RPM auto-detection)
%global __requires_exclude ^libc\\.so\\.6\\(GLIBC_PRIVATE\\)

BuildRequires:  gcc gcc-c++ make bison flex perl
BuildRequires:  readline-devel zlib-devel openssl-devel pam-devel
BuildRequires:  libxml2-devel openldap-devel libuuid-devel
BuildRequires:  libcurl-devel lz4-devel zstd-devel libssh2-devel
BuildRequires:  pkg-config libtool

Requires:       openssl-libs readline zlib libxml2 openldap libuuid libcurl lz4-libs zstd

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
sed -i 's|/usr/local/lib/libzstd.a|-lzstd|g' configure
sed -i 's|/usr/local/lib/liblz4.a|-llz4|g' configure


# Architecture flags
CFLAGS="-O2 -g -DNOLIC -Wno-error=incompatible-pointer-types -Wno-error=implicit-function-declaration -Wno-error=int-conversion -Wno-incompatible-pointer-types"
%ifarch x86_64
CFLAGS="$CFLAGS -msse4.2 -mcrc32"
%endif
%ifarch aarch64
CFLAGS="$CFLAGS -march=armv8-a"
%endif
export CFLAGS
export LDFLAGS="-Wl,-rpath,%{otb_prefix}/lib"

./configure \
    --prefix=%{otb_prefix} \
    --sysconfdir=/etc/opentenbase/%{otb_ver} \
    --datadir=%{otb_prefix}/share \
    --libdir=%{otb_prefix}/lib \
    --includedir=%{otb_prefix}/include \
    --enable-user-switch \
    --with-openssl \
    --with-uuid=e2fs \
    --with-pam \
    --with-ldap \
    --with-libxml \
    --with-lz4 \
    --with-zstd

make -j$(nproc)

# Build contrib, but skip uuid-ossp (requires OSSP UUID not available on RPM distros)
sed -i 's/^SUBDIRS += uuid-ossp/# SUBDIRS += uuid-ossp/' contrib/Makefile
sed -i 's/^ALWAYS_SUBDIRS += uuid-ossp/# ALWAYS_SUBDIRS += uuid-ossp/' contrib/Makefile
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
cat > %{buildroot}/usr/bin/opentenbase-ctl << 'CTLSCRIPT'
#!/bin/bash
# opentenbase-ctl - management script for OpenTenBase
# Usage: opentenbase-ctl {init|start|stop|restart|status|reload|psql [node]|logs [node]}
set -e
CONFIG="${OTB_CONFIG:-/etc/opentenbase/current/opentenbase.conf}"
[ -r "$CONFIG" ] || { echo "ERROR: cannot read $CONFIG" >&2; exit 1; }
. "$CONFIG"
OTB_BIN="${OTB_HOME}/bin"
TPL_DIR="$(dirname "$CONFIG")"
run_as_otb() {
    if [ "$(id -un)" = "$OTB_USER" ]; then
        PATH="$OTB_BIN:$PATH" LD_LIBRARY_PATH="$OTB_HOME/lib:${LD_LIBRARY_PATH:-}" "$@"
    else
        runuser -u "$OTB_USER" -- env PATH="$OTB_BIN:/usr/bin:/bin" LD_LIBRARY_PATH="$OTB_HOME/lib" "$@"
    fi
}
ensure_dirs() {
    install -d -o "$OTB_USER" -g "$OTB_GROUP" -m 0750 /var/log/opentenbase
    install -d -o "$OTB_USER" -g "$OTB_GROUP" -m 0700 /var/lib/opentenbase
    install -d -o "$OTB_USER" -g "$OTB_GROUP" -m 0755 /var/run/opentenbase
}
cmd_init() {
    ensure_dirs
    local start_order="$START_ORDER"
    for node in $start_order; do
        local pgdata_var="${node^^}_PGDATA"
        local pgdata="${!pgdata_var}"
        [ -z "$pgdata" ] && continue
        if [ ! -f "$pgdata/PG_VERSION" ]; then
            echo "Initializing $node ($pgdata)..."
            case "$node" in
                gtm)
                    run_as_otb "$OTB_BIN/initgtm" -Z gtm -D "$pgdata" --nodename="$node"
                    ;;
                coord*)
                    run_as_otb "$OTB_BIN/initdb" --locale=C --encoding=UTF-8 -D "$pgdata" --nodename="$node"
                    ;;
                dn*)
                    run_as_otb "$OTB_BIN/initdb" --locale=C --encoding=UTF-8 -D "$pgdata" --nodename="$node"
                    ;;
            esac
        else
            echo "$node already initialized ($pgdata)"
        fi
    done
}
cmd_start() {
    ensure_dirs
    local start_order="$START_ORDER"
    for node in $start_order; do
        local pgdata_var="${node^^}_PGDATA"
        local port_var="${node^^}_PORT"
        local log_var="${node^^}_LOG"
        local pgdata="${!pgdata_var}"
        local port="${!port_var}"
        local log="${!log_var}"
        [ -z "$pgdata" ] && continue
        case "$node" in
            gtm)
                echo "Starting GTM ($pgdata)..."
                run_as_otb "$OTB_BIN/gtm_ctl" -Z gtm -D "$pgdata" -l "$log" start
                ;;
            coord*)
                echo "Starting coordinator $node ($pgdata)..."
                run_as_otb "$OTB_BIN/pg_ctl" -Z coordinator -D "$pgdata" -l "$log" -o "-p $port" start
                ;;
            dn*)
                echo "Starting datanode $node ($pgdata)..."
                run_as_otb "$OTB_BIN/pg_ctl" -Z datanode -D "$pgdata" -l "$log" -o "-p $port" start
                ;;
        esac
    done
}
cmd_stop() {
    local stop_order="$STOP_ORDER"
    for node in $stop_order; do
        local pgdata_var="${node^^}_PGDATA"
        local pgdata="${!pgdata_var}"
        [ -z "$pgdata" ] && continue
        case "$node" in
            gtm)
                echo "Stopping GTM..."
                run_as_otb "$OTB_BIN/gtm_ctl" -Z gtm -D "$pgdata" stop 2>/dev/null || true
                ;;
            coord*)
                echo "Stopping coordinator $node..."
                run_as_otb "$OTB_BIN/pg_ctl" -Z coordinator -D "$pgdata" stop 2>/dev/null || true
                ;;
            dn*)
                echo "Stopping datanode $node..."
                run_as_otb "$OTB_BIN/pg_ctl" -Z datanode -D "$pgdata" stop 2>/dev/null || true
                ;;
        esac
    done
}
cmd_status() {
    local start_order="$START_ORDER"
    for node in $start_order; do
        local pgdata_var="${node^^}_PGDATA"
        local pgdata="${!pgdata_var}"
        [ -z "$pgdata" ] && continue
        case "$node" in
            gtm) run_as_otb "$OTB_BIN/gtm_ctl" -Z gtm -D "$pgdata" status 2>/dev/null && echo "$node: running" || echo "$node: stopped" ;;
            coord*) run_as_otb "$OTB_BIN/pg_ctl" -Z coordinator -D "$pgdata" status 2>/dev/null && echo "$node: running" || echo "$node: stopped" ;;
            dn*) run_as_otb "$OTB_BIN/pg_ctl" -Z datanode -D "$pgdata" status 2>/dev/null && echo "$node: running" || echo "$node: stopped" ;;
        esac
    done
}
case "${1:-}" in
    init) cmd_init ;;
    start) cmd_start ;;
    stop) cmd_stop ;;
    restart) cmd_stop; cmd_start ;;
    status) cmd_status ;;
    -h|--help) echo "Usage: opentenbase-ctl {init|start|stop|restart|status}" ;;
    *) echo "Usage: opentenbase-ctl {init|start|stop|restart|status}"; exit 1 ;;
esac
CTLSCRIPT
chmod 755 %{buildroot}/usr/bin/opentenbase-ctl

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
