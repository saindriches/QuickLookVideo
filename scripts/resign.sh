#!/bin/bash
#
# resign.sh <APP> <IDENTITY> <KEYCHAIN>
#
# Re-sign an app bundle inside-out with <IDENTITY>, adding the
# disable-library-validation entitlement to every code item while preserving
# each item's existing entitlements. Component discovery is generic so this
# works across QuickLookVideo v2 (previewer/thumbnailer .appex) and v3
# (Media Extension .appex). See v3 notes: the app bundles its own ffmpeg dylibs,
# and under hardened runtime Library Validation blocks a non-Apple-Team-ID
# process from loading them — disable-library-validation lifts that.
#
set -uo pipefail
APP="$1"; ID="$2"; KC="$3"
DLV="com.apple.security.cs.disable-library-validation"

sign_one() {
  local path="$1" ent
  ent="$(/usr/bin/mktemp)"
  if /usr/bin/codesign -d --entitlements - --xml "$path" >"$ent" 2>/dev/null && [ -s "$ent" ]; then
    /usr/libexec/PlistBuddy -c "Add :$DLV bool true" "$ent" >/dev/null 2>&1 \
      || /usr/libexec/PlistBuddy -c "Set :$DLV true" "$ent" >/dev/null 2>&1
  else
    /bin/cat >"$ent" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>$DLV</key><true/></dict></plist>
PLIST
  fi
  /usr/bin/codesign --force -o runtime --entitlements "$ent" -s "$ID" --keychain "$KC" "$path"
  /bin/rm -f "$ent"
}

# 1. Leaf dylibs — consistent signer, no entitlements.
while IFS= read -r -d '' d; do
  /usr/bin/codesign --force -o runtime -s "$ID" --keychain "$KC" "$d"
done < <(/usr/bin/find "$APP" -type f -name '*.dylib' -print0)

# 2. Nested code bundles (extensions, importers, generators).
while IFS= read -r -d '' b; do
  sign_one "$b"
done < <(/usr/bin/find "$APP/Contents" -type d \( -name '*.appex' -o -name '*.mdimporter' -o -name '*.qlgenerator' \) -print0)

# 3. Helper executables in Contents/MacOS other than the main app binary.
MAIN="$(/usr/bin/defaults read "$APP/Contents/Info" CFBundleExecutable 2>/dev/null || true)"
while IFS= read -r -d '' e; do
  [ "$(/usr/bin/basename "$e")" = "$MAIN" ] && continue
  sign_one "$e"
done < <(/usr/bin/find "$APP/Contents/MacOS" -type f -perm -111 -print0)

# 4. The app bundle last.
sign_one "$APP"
echo "re-sign complete: $ID"
