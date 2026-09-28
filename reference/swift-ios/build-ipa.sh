#!/bin/bash
# Build an UNSIGNED .ipa for sideloading (Sideloadly / AltStore re-sign it on
# install, so no dev account or provisioning profile is needed here).
set -euo pipefail
cd "$(dirname "$0")"

SCHEME="Exochronometer"
CONFIG="Release"
DD="build/dd"
IPA_NAME="Exochronometer.ipa"

echo ">> Building $SCHEME ($CONFIG, unsigned, device)..."
xcodebuild build \
  -project Exochronometer.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DD" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  | tail -2

APP="$DD/Build/Products/$CONFIG-iphoneos/$SCHEME.app"
if [ ! -d "$APP" ]; then
  echo "ERROR: .app not found at $APP"
  exit 1
fi

echo ">> Packaging build/$IPA_NAME ..."
rm -rf build/Payload "build/$IPA_NAME"
mkdir -p build/Payload
cp -R "$APP" build/Payload/
( cd build && zip -qry "$IPA_NAME" Payload )
rm -rf build/Payload

echo ">> Done:"
ls -lh "build/$IPA_NAME"
