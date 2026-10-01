# Dependency packages

Prebuilt dependency packages bundled for opentenbase_ctl (DEB only; the
RPM pipeline force-builds its own libpqxx at %build time).

## libpqxx 7.9.2

- `debian/` packaging for the monthly rebuild (.github/workflows/build-libpqxx.yml).
- Build notes:
  - `dh_autoreconf` is a no-op (cmake-only; the tarball has no configure
    script and regenerating one needs autoconf >= 2.71, absent on focal).
  - `debhelper-compat (= 12)` is the common denominator: focal ships
    debhelper 12.10, jammy+ ship 13.
  - `pkg-config` is a hard build dep: focal's libpq-dev lacks the server
    headers FindPostgreSQL wants, so cmake depends on its pkg-config
    fallback to locate libpq.
