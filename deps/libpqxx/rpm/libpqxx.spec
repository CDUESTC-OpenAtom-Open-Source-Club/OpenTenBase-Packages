# libpqxx 7.9.2 RPM spec for OpenTenBase opentenbase_ctl dependency
# System libpqxx (7.6.x/7.7.x) has range.hxx bugs that break opentenbase_ctl

Name:           libpqxx
Version:        7.9.2
Release:        1.opentenbase%{?dist}
Summary:        C++ library for PostgreSQL

License:        BSD-3-Clause
URL:            https://github.com/jtv/libpqxx
Source0:        https://github.com/jtv/libpqxx/archive/refs/tags/%{version}.tar.gz#/libpqxx-%{version}.tar.gz

BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  libpq-devel
BuildRequires:  make

Requires:       libpq

%description
libpqxx is a C++ library for accessing PostgreSQL databases.
It provides a set of classes and functions to make working with
PostgreSQL easier and more intuitive from C++ code.

This package (7.9.2) is specifically packaged for OpenTenBase
opentenbase_ctl which requires libpqxx >= 7.9 due to range.hxx fixes.

%package devel
Summary:        Development files for libpqxx
Requires:       %{name} = %{version}-%{release}
Requires:       libpq-devel
Requires:       cmake

%description devel
This package contains the headers and development files needed to build
applications using libpqxx 7.9.x.

%prep
%autosetup -n libpqxx-%{version}

%build
%cmake \
    -DCMAKE_INSTALL_PREFIX=%{_prefix} \
    -DBUILD_SHARED_LIBS=ON \
    -DSKIP_BUILD_TEST=ON \
    -DCMAKE_BUILD_TYPE=Release
%cmake_build

%install
%cmake_install

# Remove static library if built
rm -f %{buildroot}%{_libdir}/libpqxx.a

%ldconfig_scriptlets

%files
%license LICENSE
%doc README.md
%{_libdir}/libpqxx.so.%{version}
%{_libdir}/libpqxx.so.7

%files devel
%{_includedir}/pqxx/
%{_libdir}/libpqxx.so
%{_libdir}/cmake/libpqxx/
%{_datadir}/doc/libpqxx/

%changelog
* Wed Jul 02 2026 OpenTenBase Team <opentenbase@cduestc.edu.cn> - 7.9.2-1.opentenbase
- Initial packaging for OpenTenBase opentenbase_ctl dependency
- libpqxx 7.9.2 fixes range.hxx bugs that break opentenbase_ctl
- System libpqxx (7.6.x/7.7.x) is incompatible with opentenbase_ctl