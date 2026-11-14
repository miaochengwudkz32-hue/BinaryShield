#!/bin/bash
# Fetch X11 runtime libraries for the Avalonia Linux test WITHOUT root and WITHOUT changing the system.
# Packages are downloaded with `apt-get download` (no sudo) into a temp folder, then unpacked
# with `dpkg-deb -x` into DEST. The test then sets LD_LIBRARY_PATH to DEST so the app finds them.
#
# Usage (run inside Ubuntu, DEST on the Windows drive so the Windows side can reach it):
#   bash setup_linux_libs.sh /mnt/c/.../tests/dotnet8_avalonia/out/linux/syslibs
#
# This does not install ICU (libicu). The test uses DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 instead.

set -u
DEST="${1:?usage: setup_linux_libs.sh <dest-dir>}"
DEBS=/tmp/bs_debs
mkdir -p "$DEBS" "$DEST" || exit 1
cd "$DEBS" || exit 1

PKGS="libice6 libsm6 libxi6 libxext6 libxrender1"
apt-get download $PKGS 2>&1 | tail -n 5

for f in "$DEBS"/*.deb; do
    if dpkg-deb -x "$f" "$DEST"; then
        echo "extracted $(basename "$f")"
    else
        echo "FAILED to extract $(basename "$f")"
    fi
done

echo "--- shared libraries now in DEST (x86_64):"
find "$DEST/usr/lib/x86_64-linux-gnu" -name "*.so*" 2>/dev/null | sed "s|$DEST||" | sort | head -40
