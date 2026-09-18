#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE="onedrive-src:"
DESTINATION="gdrive-dst:OneDrive Migration"
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$ROOT/rclone.conf"
RCLONE="$ROOT/bin/rclone"
REPORT_DIR="$ROOT/reports"

die() {
  printf '\nFAILED: %s\n' "$*" >&2
  exit 1
}

require() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' is not installed."
}

install_rclone() {
  require curl
  require python3

  local arch
  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    armv7l) arch="arm-v7" ;;
    *) die "Unsupported CPU architecture: $(uname -m)" ;;
  esac

  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  printf 'Installing portable rclone for linux-%s...\n' "$arch"
  curl --fail --location --silent --show-error --retry 3 \
    "https://downloads.rclone.org/rclone-current-linux-${arch}.zip" \
    --output "$tmp/rclone.zip"

  python3 -m zipfile -e "$tmp/rclone.zip" "$tmp/unpacked"

  local extracted
  extracted="$(find "$tmp/unpacked" -type f -name rclone -print -quit)"
  [[ -n "$extracted" ]] || die "Downloaded archive did not contain rclone."

  mkdir -p "$(dirname "$RCLONE")"
  install -m 0755 "$extracted" "$RCLONE"
}

preview_report() {
  local file="$1"
  local label="$2"
  [[ -s "$file" ]] || return 0
  printf '\n--- %s (first 30) ---\n' "$label"
  sed -n '1,30p' "$file"
}

VERIFY_MISSING=0
VERIFY_DIFFER=0
VERIFY_ERRORS=0

verify() {
  local tag="$1"
  local missing="$REPORT_DIR/${tag}-missing-on-dst.txt"
  local differ="$REPORT_DIR/${tag}-different.txt"
  local errors="$REPORT_DIR/${tag}-errors.txt"

  rm -f "$missing" "$differ" "$errors"

  set +e
  "$RCLONE" check "$SOURCE" "$DESTINATION" \
    --config "$CONFIG" \
    --one-way \
    --size-only \
    --missing-on-dst "$missing" \
    --differ "$differ" \
    --error "$errors" \
    --checkers 8 \
    --stats 30s \
    --stats-one-line-date
  local rc=$?
  set -e

  touch "$missing" "$differ" "$errors"
  VERIFY_MISSING="$(wc -l < "$missing" | tr -d ' ')"
  VERIFY_DIFFER="$(wc -l < "$differ" | tr -d ' ')"
  VERIFY_ERRORS="$(wc -l < "$errors" | tr -d ' ')"

  printf 'Check result: missing=%s, different_size=%s, errors=%s\n' \
    "$VERIFY_MISSING" "$VERIFY_DIFFER" "$VERIFY_ERRORS"

  if (( rc == 0 )); then
    return 0
  fi
  if (( VERIFY_ERRORS > 0 )); then
    preview_report "$errors" "check errors"
    return 2
  fi
  if (( VERIFY_MISSING > 0 || VERIFY_DIFFER > 0 )); then
    preview_report "$missing" "missing on Google Drive"
    preview_report "$differ" "different size"
    return 1
  fi

  return 2
}

[[ -f "$CONFIG" ]] || die "Missing remote rclone.conf: $CONFIG"
chmod 600 "$CONFIG"
mkdir -p "$REPORT_DIR"

if [[ ! -x "$RCLONE" ]]; then
  install_rclone
fi

printf 'Using: '
"$RCLONE" version | head -n 1

remotes="$("$RCLONE" listremotes --config "$CONFIG")"
grep -Fxq 'onedrive-src:' <<<"$remotes" || die "rclone.conf is missing remote 'onedrive-src:'."
grep -Fxq 'gdrive-dst:' <<<"$remotes" || die "rclone.conf is missing remote 'gdrive-dst:'."

printf '\nValidating OneDrive access...\n'
"$RCLONE" lsf "$SOURCE" --config "$CONFIG" --max-depth 1 >/dev/null
printf 'Validating Google Drive access...\n'
"$RCLONE" lsf "gdrive-dst:" --config "$CONFIG" --max-depth 1 >/dev/null

printf '\nChecking existing folder: OneDrive Migration\n'
set +e
verify "before"
check_rc=$?
set -e

case "$check_rc" in
  0)
    printf '\nCOMPLETE: every OneDrive file is already present with the same size. Nothing to copy.\n'
    exit 0
    ;;
  1)
    printf '\nINCOMPLETE: resuming copy. Existing same-size files will be skipped.\n'
    ;;
  *)
    die "Verification could not complete reliably. Copy was not started."
    ;;
esac

"$RCLONE" copy "$SOURCE" "$DESTINATION" \
  --config "$CONFIG" \
  --size-only \
  --transfers 4 \
  --checkers 8 \
  --create-empty-src-dirs \
  --stats 10s \
  --stats-one-line-date

printf '\nCopy finished. Verifying again...\n'
set +e
verify "after"
final_rc=$?
set -e

if (( final_rc == 0 )); then
  printf '\nCOMPLETE: resumed copy finished and verification passed.\n'
  exit 0
fi

die "Final verification failed. Reports are in $REPORT_DIR."
