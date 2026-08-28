#!/usr/bin/env bash

set -Eeuo pipefail

# App Store Connect API credentials. Override with environment variables only
# when the owning account rotates these values.
ASC_KEY_ID="${ASC_KEY_ID:-AMDBKB83K9}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-3659a31c-d035-4195-842f-d269268a59c3}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-D33974QQTD}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_AMDBKB83K9.p8}"

PROJECT_NAME="DataCenterTycoon"
EXPORT_PRESET="iOS Release Candidate"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRESET_FILE="$ROOT_DIR/export_presets.cfg"
IOS_EXPORT_DIR="$ROOT_DIR/builds/ios"
XCODE_PROJECT="$IOS_EXPORT_DIR/$PROJECT_NAME.xcodeproj"
ARCHIVE_DIR="$ROOT_DIR/builds/archives"
IPA_ROOT="$ROOT_DIR/builds/ipa"

BUMP=false
UPLOAD=false
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: tools/release_ios.sh [--bump] [--upload] [--dry-run]

  --bump    Increment the iOS build number before exporting.
  --upload  Upload the verified IPA to App Store Connect.
  --dry-run Run the complete export/sign/archive/IPA chain without uploading.
EOF
}

while (($# > 0)); do
  case "$1" in
    --bump) BUMP=true ;;
    --upload) UPLOAD=true ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if $DRY_RUN && $UPLOAD; then
  echo "--dry-run and --upload cannot be used together." >&2
  exit 2
fi

on_error() {
  local line="$1"
  echo "Release stopped at line $line. Nothing was uploaded unless the upload step had already begun." >&2
}
trap 'on_error "$LINENO"' ERR

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required tool not found: $1" >&2
    exit 1
  fi
}

require_command godot
require_command python3
require_command xcodebuild
require_command xcrun
require_command codesign
require_command unzip

if [[ ! -f "$ASC_KEY_PATH" ]]; then
  echo "App Store Connect API key not found: $ASC_KEY_PATH" >&2
  exit 1
fi

if $BUMP; then
  python3 - "$PRESET_FILE" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
pattern = r'(?m)^application/version="(\d+)"$'
match = re.search(pattern, text)
if match is None:
    raise SystemExit("Could not find application/version in export_presets.cfg")
new_build = int(match.group(1)) + 1
text, count = re.subn(pattern, f'application/version="{new_build}"', text, count=1)
if count != 1:
    raise SystemExit("Build number update was not unique")
path.write_text(text, encoding="utf-8")
print(new_build)
PY
  echo "Build number incremented. Commit export_presets.cfg with the release commit."
fi

BUILD_NUMBER="$(sed -n 's/^application\/version="\([0-9][0-9]*\)"$/\1/p' "$PRESET_FILE" | head -1)"
SHORT_VERSION="$(sed -n 's/^application\/short_version="\([^"]*\)"$/\1/p' "$PRESET_FILE" | head -1)"
if [[ -z "$BUILD_NUMBER" || -z "$SHORT_VERSION" ]]; then
  echo "Could not read the iOS version from export_presets.cfg." >&2
  exit 1
fi

ARCHIVE_PATH="$ARCHIVE_DIR/$PROJECT_NAME-$SHORT_VERSION-$BUILD_NUMBER.xcarchive"
IPA_DIR="$IPA_ROOT/$SHORT_VERSION-$BUILD_NUMBER"
EXPORT_OPTIONS="$IPA_ROOT/ExportOptions-$BUILD_NUMBER.plist"
UPLOAD_LOG="$IPA_ROOT/upload-$BUILD_NUMBER.log"

echo "Preparing $PROJECT_NAME $SHORT_VERSION ($BUILD_NUMBER)"
mkdir -p "$ARCHIVE_DIR" "$IPA_ROOT"
rm -rf "$IOS_EXPORT_DIR" "$ARCHIVE_PATH" "$IPA_DIR"
mkdir -p "$IOS_EXPORT_DIR" "$IPA_DIR"

echo "1/5 Exporting the Godot iOS project…"
godot --headless --path "$ROOT_DIR" --export-release "$EXPORT_PRESET" "$IOS_EXPORT_DIR/$PROJECT_NAME.zip"

if [[ ! -d "$XCODE_PROJECT" ]]; then
  echo "Godot did not create $XCODE_PROJECT" >&2
  exit 1
fi

echo "2/5 Applying signing and sanitizing unused privacy keys…"
python3 - "$XCODE_PROJECT/project.pbxproj" "$APPLE_TEAM_ID" "$IOS_EXPORT_DIR/$PROJECT_NAME/$PROJECT_NAME-Info.plist" <<'PY'
from pathlib import Path
import plistlib
import re
import sys

path = Path(sys.argv[1])
team = sys.argv[2]
info_path = Path(sys.argv[3])
text = path.read_text(encoding="utf-8")
text = re.sub(r'CODE_SIGN_STYLE = "?Manual"?;', 'CODE_SIGN_STYLE = Automatic;', text)
text = re.sub(r'CODE_SIGN_IDENTITY = "[^"]*";', 'CODE_SIGN_IDENTITY = "Apple Development";', text)
text = re.sub(r'DEVELOPMENT_TEAM = [^;]*;', f'DEVELOPMENT_TEAM = {team};', text)
path.write_text(text, encoding="utf-8")

with info_path.open("rb") as handle:
    info = plistlib.load(handle)
for key in ("NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSPhotoLibraryUsageDescription"):
    if not str(info.get(key, "")).strip():
        info.pop(key, None)
with info_path.open("wb") as handle:
    plistlib.dump(info, handle, sort_keys=False)
PY

AUTH_ARGS=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$ASC_KEY_PATH"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
)

echo "3/5 Archiving and signing…"
xcodebuild \
  -project "$XCODE_PROJECT" \
  -scheme "$PROJECT_NAME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  "${AUTH_ARGS[@]}"

ARCHIVED_APP="$ARCHIVE_PATH/Products/Applications/$PROJECT_NAME.app"
if [[ ! -d "$ARCHIVED_APP" ]]; then
  echo "Archive completed without the expected app: $ARCHIVED_APP" >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "$ARCHIVED_APP"

cat > "$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key><string>export</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>method</key><string>app-store-connect</string>
  <key>signingStyle</key><string>automatic</string>
  <key>stripSwiftSymbols</key><true/>
  <key>teamID</key><string>$APPLE_TEAM_ID</string>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
EOF

echo "4/5 Exporting and verifying the IPA…"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$IPA_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  "${AUTH_ARGS[@]}"

IPA_PATH="$(find "$IPA_DIR" -maxdepth 1 -type f -name '*.ipa' -print -quit)"
if [[ -z "$IPA_PATH" ]]; then
  echo "No IPA was produced in $IPA_DIR" >&2
  exit 1
fi

VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dct-ipa-verify.XXXXXX")"
trap 'rm -rf "$VERIFY_DIR"' EXIT
unzip -q "$IPA_PATH" -d "$VERIFY_DIR"
EXPORTED_APP="$(find "$VERIFY_DIR/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
if [[ -z "$EXPORTED_APP" ]]; then
  echo "The IPA does not contain an app bundle." >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "$EXPORTED_APP"

echo "5/5 IPA verified: $IPA_PATH"

if $UPLOAD; then
  echo "Uploading build $BUILD_NUMBER to App Store Connect…"
  set +e
  xcrun altool --upload-app \
    --file "$IPA_PATH" \
    --type ios \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID" 2>&1 | tee "$UPLOAD_LOG"
  upload_status=${PIPESTATUS[0]}
  set -e
  if ((upload_status != 0)); then
    if grep -q 'ENTITY_ERROR\.ATTRIBUTE\.INVALID\.DUPLICATE' "$UPLOAD_LOG"; then
      echo "App Store Connect already has build $BUILD_NUMBER. Run tools/release_ios.sh --bump --upload." >&2
    else
      echo "Upload failed. See $UPLOAD_LOG" >&2
    fi
    exit "$upload_status"
  fi
  echo "Upload accepted by App Store Connect."
elif $DRY_RUN; then
  echo "Dry run complete: the full release chain passed and nothing was uploaded."
else
  echo "Release artifact is ready. Re-run with --upload only after reviewing this IPA."
fi
