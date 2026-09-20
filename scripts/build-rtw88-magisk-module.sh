#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$HOME/bluejay-kernel-src}"
OUT="/tmp/rtw88-magisk"

rm -rf "$OUT"
mkdir -p "$OUT/system/vendor/firmware/rtw88"

cp "$ROOT/out/bluejay/dist/rtw_core.ko" "$OUT/"
cp "$ROOT/out/bluejay/dist/rtw_usb.ko" "$OUT/"
cp "$ROOT/out/bluejay/dist/rtw_88xxa.ko" "$OUT/"
cp "$ROOT/out/bluejay/dist/rtw_8812a.ko" "$OUT/"
cp "$ROOT/out/bluejay/dist/rtw_8812au.ko" "$OUT/"
cp "$ROOT/private/google-modules/rtw88/firmware/rtw8812a_fw.bin" "$OUT/system/vendor/firmware/rtw88/"

cat > "$OUT/module.prop" <<'EOF'
id=rtw88bluejay
name=Bluejay RTW88 WiFi
version=1.0
versionCode=1
author=m4ckDev
description=RTL8812AU RTW88 driver and firmware for Bluejay
EOF

cat > "$OUT/service.sh" <<'EOF'
#!/system/bin/sh
MODDIR="$(dirname "$0")"
sleep 3
insmod "$MODDIR/rtw_core.ko" 2>/dev/null
insmod "$MODDIR/rtw_usb.ko" 2>/dev/null
insmod "$MODDIR/rtw_88xxa.ko" 2>/dev/null
insmod "$MODDIR/rtw_8812a.ko" 2>/dev/null
insmod "$MODDIR/rtw_8812au.ko" 2>/dev/null
EOF

chmod 755 "$OUT/service.sh"

echo "Created: $OUT"
find "$OUT" -type f -printf '%P\n'
