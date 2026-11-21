#!/bin/bash
# macOS + Xcode 16.4 + XcodeGen. No Apple developer account/certificate required.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-$PWD/dist}"
mkdir -p "$OUT/logs"
OUT=$(cd "$OUT" && pwd)
xcodegen generate
xcodebuild -skipMacroValidation -project STV.xcodeproj -scheme STV -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath DerivedDataIOS16 \
  ONLY_ACTIVE_ARCH=NO IPHONEOS_DEPLOYMENT_TARGET=16.0 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=YES ENABLE_DEBUG_DYLIB=NO \
  build 2>&1 | tee "$OUT/logs/ios16-build.log"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload"
APP="$STAGE/Payload/STV.app"
ditto DerivedDataIOS16/Build/Products/Release-iphoneos/STV.app "$APP"
# Ad-hoc signatures are replaced by TrollStore on installation. Keep the ordinary app sandbox.
if [[ -d "$APP/Frameworks" ]]; then
  while IFS= read -r -d '' item; do
    codesign --force --sign - --timestamp=none "$item"
  done < <(find "$APP/Frameworks" -depth \( -name '*.framework' -o -name '*.dylib' \) -print0)
fi
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
python3 scripts/verify-ios16-package.py "$APP" | tee "$OUT/logs/package-validation.json"
IPA="$OUT/iDuanJu-iOS16-TrollStore.ipa"
(cd "$STAGE" && /usr/bin/zip -qry "$IPA" Payload)
shasum -a 256 "$IPA" | tee "$OUT/SHA256SUMS.txt"
echo "Created $IPA"
