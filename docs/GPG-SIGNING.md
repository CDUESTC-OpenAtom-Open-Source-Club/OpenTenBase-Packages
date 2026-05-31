# GPG Package Signing

This document explains how OpenTenBase packages are GPG-signed, how to set up
signing for CI releases, and how end users can verify package authenticity.

## Overview

Every release can include GPG signatures for both DEB and RPM packages. When
signing is configured, the release workflow will:

1. Import the GPG private key from the `GPG_PRIVATE_KEY` repository secret
2. Sign all `.deb` packages (inline signature via `dpkg-sig`, or detached `.sig` as fallback)
3. Sign all `.rpm` packages (via `rpmsign --addsign`)
4. Export the public key as `opentenbase-gpg-key.asc`
5. Upload signatures and the public key alongside the packages in the GitHub Release

When signing is **not** configured, releases proceed normally without signatures.
The signing step is fully optional and does not block the release.

## Setting Up GPG Signing (Maintainers)

### Step 1: GPG Key Pair (Already Configured)

The signing key is already set up:

| Field | Value |
|-------|-------|
| **Fingerprint** | `D8B2E316E1FF88EE178703549D8FA46F3A55D5F0` |
| **Key ID** | `9D8FA46F3A55D5F0` |
| **Type** | RSA 4096-bit |
| **Identity** | OpenTenBase Packages <packages@opentenbase.org> |
| **Expiration** | None |

If you need to generate a new key:

```bash
gpg --full-generate-key
```

Recommended settings:
- Key type: RSA 4096-bit (best compatibility) or Ed25519 (modern)
- Expiration: none (or set a long expiry and plan to rotate)
- Name/Email: use the project maintainer identity

### Step 2: Export the Private Key

Export the ASCII-armored private key. This will be stored as a GitHub secret.

```bash
# List keys to find your key ID
gpg --list-secret-keys --keyid-format long

# Export the private key (ASCII-armored)
gpg --armor --export-secret-keys YOUR_KEY_ID > private-key.asc
```

### Step 3: Add GitHub Repository Secrets

Go to your GitHub repository: **Settings > Secrets and variables > Actions**

Add these two secrets:

| Secret Name        | Value                              | Required |
|--------------------|------------------------------------|----------|
| `GPG_PRIVATE_KEY`  | Contents of `private-key.asc`      | Yes      |
| `GPG_PASSPHRASE`   | Passphrase for the GPG key         | No (omit if key has no passphrase) |

**Important:** Copy the **entire** content of `private-key.asc`, including the
`-----BEGIN PGP PRIVATE KEY BLOCK-----` and `-----END PGP PRIVATE KEY BLOCK-----`
lines.

### Step 4: Distribute the Public Key

Export the public key and commit it to the repository so users can verify packages.
The canonical in-repo copy lives at `scripts/opentenbase-packages-key.asc`:

```bash
gpg --armor --export YOUR_KEY_ID > scripts/opentenbase-packages-key.asc
```

The public key is also automatically included in every signed release as
`opentenbase-gpg-key.asc`, and published on the package repository site as
`gpg-key.asc`.

### Step 5: Verify the Setup

Push a tag to trigger a release. In the Actions log, look for:

```
[STEP]  Importing GPG key from environment...
[INFO]  Imported GPG key: ABCD1234EFGH5678
[STEP]  Signing DEB packages...
[INFO]  DEB signing complete: X signed, 0 failed
[STEP]  Signing RPM packages...
[INFO]  RPM signing complete: X signed, 0 failed
```

If the `GPG_PRIVATE_KEY` secret is not set, the workflow will print:

```
GPG signing is skipped (no GPG_PRIVATE_KEY secret)
```

and continue with unsigned packages.

## Verifying Packages (End Users)

### Install the Public Key

```bash
# From a release
curl -sLO https://github.com/muzimu217/OpenTenBase-deb/releases/latest/download/opentenbase-gpg-key.asc
gpg --import opentenbase-gpg-key.asc

# Or from the repository
curl -sLO https://raw.githubusercontent.com/muzimu217/OpenTenBase-deb/main/scripts/opentenbase-packages-key.asc
gpg --import opentenbase-packages-key.asc
```

### Verify the Key Fingerprint (Recommended)

Before trusting the key, confirm it matches the published fingerprint:

```bash
gpg --show-keys opentenbase-packages-key.asc | grep -A1 pub
# Expected fingerprint:
#   D8B2E316 E1FF88EE 17870354 9D8FA46F 3A55D5F0
```

The `setup-apt.sh` / `setup-rpm.sh` scripts perform this check automatically and
abort if the downloaded key does not match this fingerprint.

### Verify a DEB Package

OpenTenBase DEB packages are signed using one of two methods:

**Method 1: Inline signature (dpkg-sig)**

```bash
# Install dpkg-sig if not present
sudo apt-get install dpkg-sig

# Verify
dpkg-sig --verify opentenbase_5.0-1ubuntu1~noble_amd64.deb
```

**Method 2: Detached signature (.sig file)**

```bash
# Download both the .deb and its .sig file
gpg --verify opentenbase_5.0-1ubuntu1~noble_amd64.deb.sig opentenbase_5.0-1ubuntu1~noble_amd64.deb
```

### Verify an RPM Package

```bash
# Import the key first
rpm --import opentenbase-gpg-key.asc

# Verify
rpm --checksig opentenbase-5.0-1.el9.x86_64.rpm
```

### Verify Checksums

Every release includes `checksums.sha256`. Verify file integrity:

```bash
# Download checksums and packages, then:
sha256sum --check checksums.sha256
```

## Local Signing (Without CI)

For manual releases or testing, you can sign packages locally:

```bash
# Sign DEB packages
./scripts/sign-packages.sh --deb-dir ./debs

# Sign RPM packages
./scripts/sign-packages.sh --rpm-dir ./rpms

# Sign both and export public key
./scripts/sign-packages.sh --deb-dir ./debs --rpm-dir ./rpms --export public.asc

# Verify signatures
./scripts/sign-packages.sh --verify-deb ./debs --verify-rpm ./rpms
```

## Troubleshooting

### "gpg: signing failed: No passphrase"

The key has a passphrase but none was provided. Set `GPG_PASSPHRASE` in your
GitHub secrets.

### "gpg: signing failed: No secret key"

The `GPG_PRIVATE_KEY` secret does not contain a valid private key. Re-export
and re-set the secret.

### RPM signing fails with "error: You must set "%_gpg_name""

The rpmsign tool needs the key identity. Ensure the key was imported correctly
by the CI script. The script configures `%_gpg_name` automatically.

### Packages show as "unsigned" after release

Check the Actions log for the signing step. If the `GPG_PRIVATE_KEY` secret
is not set, signing is silently skipped. This is by design.

## Key Rotation

When rotating GPG keys:

1. Generate a new key pair
2. Update `GPG_PRIVATE_KEY` and `GPG_PASSPHRASE` secrets
3. Export the new public key and commit it
4. Old signatures remain valid if users still have the old public key imported
5. Consider including both old and new public keys in releases during transition
