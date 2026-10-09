#!/bin/sh
# ci/install-toolchain.sh
#
# Installs the pinned CI toolchain into a debian:trixie container, run as
# root by the workflows in .github/workflows/ after checkout.
#
# Provenance of ci/checksums.sha256 (recorded 2026-09-27; both files were
# downloaded twice and their SHA-256 sums matched across downloads before
# being written to that file):
#   - ccl-1.13-linuxx86.tar.gz
#     https://github.com/Clozure/ccl/releases/download/v1.13/ccl-1.13-linuxx86.tar.gz
#   - ocicl_2.9.0-1_amd64.deb
#     https://github.com/ocicl/ocicl/releases/download/v2.9.0/ocicl_2.9.0-1_amd64.deb
set -eu

CCL_URL="https://github.com/Clozure/ccl/releases/download/v1.13/ccl-1.13-linuxx86.tar.gz"
OCICL_DEB_URL="https://github.com/ocicl/ocicl/releases/download/v2.9.0/ocicl_2.9.0-1_amd64.deb"

# Resolve ci/checksums.sha256 next to this script, regardless of the
# caller's working directory.
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
checksums=$script_dir/checksums.sha256

# Debian trixie ships the pin exactly: cmark-gfm 0.29.0.gfm.13, SBCL 2.5.2,
# ECL 24.5.10. No -dev packages: discovery must see what a user sees, and
# a user needs only the runtime packages.
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  sbcl ecl cmark-gfm libcmark-gfm0.29.0.gfm.13 libcmark-gfm-extensions0.29.0.gfm.13 \
  make git ca-certificates curl

# CCL 1.13 has no Debian package and no arm64 build; this job is
# amd64-only. Fetch both pinned artifacts and verify them
# before unpacking or installing anything from them.
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT INT TERM
cd "$workdir"
curl -fsSL -o ccl-1.13-linuxx86.tar.gz "$CCL_URL"
curl -fsSL -o ocicl_2.9.0-1_amd64.deb "$OCICL_DEB_URL"
sha256sum -c "$checksums"

# The tarball's top-level directory is already "ccl/", so extracting into
# /opt lands the kernel and image at /opt/ccl/lx86cl64(.image).
mkdir -p /opt
tar -xzf ccl-1.13-linuxx86.tar.gz -C /opt

# The kernel binary is named lx86cl64, not ccl; wrap it under the name the
# rest of the project expects. Verified: it locates lx86cl64.image next to
# its own real path, so no CCL_DEFAULT_DIRECTORY is needed even when
# exec'd by absolute path from an unrelated cwd.
cat >/usr/local/bin/ccl <<'WRAP'
#!/bin/sh
exec /opt/ccl/lx86cl64 "$@"
WRAP
chmod +x /usr/local/bin/ccl

# ocicl has no apt package; install its verified .deb directly.
apt-get install -y ./ocicl_2.9.0-1_amd64.deb

# One-time setup, required before `ocicl install`. Stdin is /dev/null:
# ocicl can otherwise sit waiting on a terminal it doesn't have.
ocicl setup </dev/null
