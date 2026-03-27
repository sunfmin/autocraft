#!/bin/bash
# Extract screenshots from an xcresult bundle into a screenshots/ subfolder
# with clean names (stripping UUID suffixes).
#
# Usage:
#   extract-screenshots.sh <xcresult-path> <output-dir>
#
# Example:
#   extract-screenshots.sh /tmp/test-results.xcresult journeys/first-launch-setup/screenshots
#
# If <xcresult-path> is omitted, uses the most recent xcresult in DerivedData
# for the Xcode project in the current directory.

set -euo pipefail

XCRESULT="${1:-}"
OUTPUT_DIR="${2:-.}"
TMPDIR_EXTRACT="$(mktemp -d)"

trap 'rm -rf "$TMPDIR_EXTRACT"' EXIT

# Auto-detect xcresult if not provided
if [[ -z "$XCRESULT" ]]; then
  PROJECT=$(ls -d *.xcodeproj 2>/dev/null | head -1 | sed 's/.xcodeproj//')
  if [[ -z "$PROJECT" ]]; then
    echo "Error: No .xcodeproj found in current directory and no xcresult path provided." >&2
    exit 1
  fi

  DD_DIR="$HOME/Library/Developer/Xcode/DerivedData"
  XCRESULT=$(find "$DD_DIR" -name "*.xcresult" -path "*${PROJECT}*" -print0 2>/dev/null \
    | xargs -0 ls -dt 2>/dev/null \
    | head -1)

  if [[ -z "$XCRESULT" ]]; then
    echo "Error: No xcresult found for project '$PROJECT' in DerivedData." >&2
    exit 1
  fi
  echo "Using xcresult: $XCRESULT"
fi

if [[ ! -d "$XCRESULT" ]]; then
  echo "Error: xcresult not found at: $XCRESULT" >&2
  exit 1
fi

# Clean and recreate output directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Export all attachments to a temp directory
xcrun xcresulttool export attachments \
  --path "$XCRESULT" \
  --output-path "$TMPDIR_EXTRACT" 2>&1

MANIFEST="$TMPDIR_EXTRACT/manifest.json"
if [[ ! -f "$MANIFEST" ]]; then
  echo "Error: No manifest.json generated — no attachments found." >&2
  exit 1
fi

# Read manifest and copy files with clean names
python3 -c "
import json, re, sys

with open('$MANIFEST') as f:
    data = json.load(f)

for test in data:
    for att in test['attachments']:
        src = att['exportedFileName']
        suggested = att['suggestedHumanReadableName']
        # Strip '_N_UUID' suffix: 'name_0_XXXXXXXX-...-XXXXXXXXXXXX.ext' -> 'name.ext'
        clean = re.sub(r'_\d+_[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}', '', suggested)
        print(f'{src}\t{clean}')
" | while IFS=$'\t' read -r src clean; do
  if [[ -f "$TMPDIR_EXTRACT/$src" ]]; then
    cp "$TMPDIR_EXTRACT/$src" "$OUTPUT_DIR/$clean"
    echo "  $clean"
  fi
done

COUNT=$(find "$OUTPUT_DIR" -name '*.png' | wc -l | tr -d ' ')
echo "Extracted $COUNT screenshots to $OUTPUT_DIR/"
