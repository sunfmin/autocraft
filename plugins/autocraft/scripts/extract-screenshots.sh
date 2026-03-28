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

# Read manifest and copy files with clean, timestamped names.
# Each screenshot gets a monotonic timestamp prefix (T+seconds from first
# attachment) so reviewers can see *when* each screenshot was taken during
# the test run and spot long gaps between steps.
python3 -c "
import json, re, sys, os

with open('$MANIFEST') as f:
    data = json.load(f)

# Collect all attachments with their timestamps
entries = []
for test in data:
    for att in test['attachments']:
        src = att['exportedFileName']
        suggested = att['suggestedHumanReadableName']
        # Strip '_N_UUID' suffix
        clean = re.sub(r'_\d+_[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}', '', suggested)
        # Get file modification time as proxy for capture time
        src_path = os.path.join('$TMPDIR_EXTRACT', src)
        mtime = os.path.getmtime(src_path) if os.path.exists(src_path) else 0
        entries.append((mtime, src, clean))

# Sort by capture time
entries.sort(key=lambda e: e[0])

# Compute T+offset from first screenshot
t0 = entries[0][0] if entries else 0
for mtime, src, clean in entries:
    elapsed = mtime - t0
    minutes = int(elapsed) // 60
    seconds = int(elapsed) % 60
    # Prefix: T00m00s — monotonic elapsed time from test start
    ts_prefix = f'T{minutes:02d}m{seconds:02d}s'
    name_part, ext = os.path.splitext(clean)
    stamped = f'{ts_prefix}_{name_part}{ext}'
    print(f'{src}\t{stamped}')
" | while IFS=$'\t' read -r src stamped; do
  if [[ -f "$TMPDIR_EXTRACT/$src" ]]; then
    cp "$TMPDIR_EXTRACT/$src" "$OUTPUT_DIR/$stamped"
    echo "  $stamped"
  fi
done

COUNT=$(find "$OUTPUT_DIR" -name '*.png' | wc -l | tr -d ' ')
echo "Extracted $COUNT screenshots to $OUTPUT_DIR/"
