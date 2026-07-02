# Vendor Dependencies

This directory serves as the **canonical location** for vendored third-party source
tarballs that are needed at build time across multiple packaging formats (DEB / RPM).

## Current Vendored Dependencies

| File | Version | Purpose | Used By |
|------|---------|---------|---------|
| `libssh2-1.11.1.tar.gz` | 1.11.1 | SSH library (Rocky 9 / openEuler compatibility) | RPM spec (Source3), opentenbase_ctl |

## Why Vendored?

- **libssh2** — Not available in Rocky Linux 9 / openEuler official repos.
  Bundled into the RPM package as Source3 for `rpmbuild`. The compiled library
  (`libssh2.so.1`) is included in `/usr/lib/opentenbase/5.0/lib/` for runtime.

## Build Integration

- **RPM**: `rpm/build-rpm.sh` copies from `vendor/` to `$RPMBUILD_DIR/SOURCES/`
- **Docker**: Not needed — RPM package already includes `libssh2.so.1`

## Adding New Vendored Dependencies

1. Place the source tarball in this directory
2. Update this README with version and purpose
3. Reference from `$SCRIPT_DIR/../vendor/` in build scripts
4. Do NOT copy to `rpm/` or `docker/` — use the single copy here