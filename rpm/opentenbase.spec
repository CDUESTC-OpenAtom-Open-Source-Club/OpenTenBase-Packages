Name:           opentenbase
Version:        5.0.0
Release:        1
Summary:        OpenTenBase distributed database system
License:        BSD
URL:            https://github.com/OpenTenBase/OpenTenBase
BuildArch:      aarch64
Source0:        opentenbase-5.0-aarch64.tar.gz

%define otb_version 5.0

%description
OpenTenBase is an advanced enterprise-level database management system
based on PostgreSQL. It supports distributed transactions, parallel
computing, security, management, and audit functions.

%prep
%setup -q -c -n opentenbase

%install
mkdir -p %{buildroot}/usr/lib/opentenbase/%{otb_version}
cp -a bin %{buildroot}/usr/lib/opentenbase/%{otb_version}/
cp -a lib %{buildroot}/usr/lib/opentenbase/%{otb_version}/
cp -a share %{buildroot}/usr/lib/opentenbase/%{otb_version}/
cp -a include %{buildroot}/usr/lib/opentenbase/%{otb_version}/

mkdir -p %{buildroot}/usr/bin
for f in %{buildroot}/usr/lib/opentenbase/%{otb_version}/bin/*; do
    bname=$(basename "$f")
    ln -s /usr/lib/opentenbase/%{otb_version}/bin/"$bname" %{buildroot}/usr/bin/"$bname"
done

mkdir -p %{buildroot}/etc/ld.so.conf.d
echo '/usr/lib/opentenbase/%{otb_version}/lib' > %{buildroot}/etc/ld.so.conf.d/opentenbase.conf

# Versioned config directories
mkdir -p %{buildroot}/etc/opentenbase/%{otb_version}
mkdir -p %{buildroot}/var/lib/opentenbase/%{otb_version}
mkdir -p %{buildroot}/var/log/opentenbase/%{otb_version}
mkdir -p %{buildroot}/var/run/opentenbase

# Version marker
echo "%{otb_version}" > %{buildroot}/usr/lib/opentenbase/%{otb_version}/VERSION

%files
/usr/lib/opentenbase/%{otb_version}
/usr/bin/*
/etc/ld.so.conf.d/opentenbase.conf
%dir /etc/opentenbase/%{otb_version}
%dir /var/lib/opentenbase/%{otb_version}
%dir /var/log/opentenbase/%{otb_version}
%dir /var/run/opentenbase

%post
ldconfig
# Set up /etc/opentenbase/current symlink for version switching
if [ ! -L /etc/opentenbase/current ]; then
    ln -sf /etc/opentenbase/%{otb_version} /etc/opentenbase/current
fi
# Create system user if not exists
if ! getent group opentenbase >/dev/null 2>&1; then
    groupadd --system opentenbase 2>/dev/null || true
fi
if ! getent passwd opentenbase >/dev/null 2>&1; then
    useradd --system --gid opentenbase --home-dir /var/lib/opentenbase \
        --shell /bin/bash --comment "OpenTenBase administrator" opentenbase 2>/dev/null || true
fi
chown opentenbase:opentenbase /var/lib/opentenbase/%{otb_version}
chown opentenbase:opentenbase /var/log/opentenbase/%{otb_version}
chown opentenbase:opentenbase /var/run/opentenbase

%postun
ldconfig
