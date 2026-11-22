#!/bin/bash
set -euo pipefail

if [[ ! "${ZHANAR_DEVELOPMENT_TEAM:-}" =~ ^[A-Z0-9]{10}$ ]]; then
  printf 'Set ZHANAR_DEVELOPMENT_TEAM to the owner Apple Developer Team ID (10 uppercase letters/digits).\n' >&2
  exit 2
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${ZHANAR_BUILD_DIR:-${SCRIPT_DIR}/build/AppStore}"
ARCHIVE_PATH="${OUTPUT_DIR}/ZHANAR.xcarchive"
EXPORT_PATH="${OUTPUT_DIR}/Export"

mkdir -p "$OUTPUT_DIR"

python3 "$SCRIPT_DIR/scripts/validate_product_ids.py"
python3 "$SCRIPT_DIR/scripts/validate_app_store_listing.py"

xcodebuild archive \
  -project "$SCRIPT_DIR/Massage app.xcodeproj" \
  -scheme "Massage app" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$OUTPUT_DIR/DerivedData" \
  -archivePath "$ARCHIVE_PATH" \
  "DEVELOPMENT_TEAM=$ZHANAR_DEVELOPMENT_TEAM" \
  -allowProvisioningUpdates

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$SCRIPT_DIR/AppStoreExportOptions.plist" \
  -allowProvisioningUpdates

printf 'App Store export created at: %s\n' "$EXPORT_PATH"
