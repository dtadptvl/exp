#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE="onedrive-src:"
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${1:-$ROOT/rclone.conf}"
DESTINATION_FOLDER="${2:-OneDrive Migration 2}"
DESTINATION="gdrive-dst:${DESTINATION_FOLDER}"
RCLONE="$ROOT/bin/rclone"
REPORT_DIR="$ROOT/reports"

cancel() {
  trap - INT TERM HUP
  printf '\nCANCELLED by user. No source data was changed.\n' >&2
  exit 130
}
trap cancel INT TERM HUP

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

verify() {
  local missing="$REPORT_DIR/final-missing-on-dst.txt"
  local differ="$REPORT_DIR/final-different.txt"
  local errors="$REPORT_DIR/final-errors.txt"

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
  local missing_count differ_count error_count
  missing_count="$(wc -l < "$missing" | tr -d ' ')"
  differ_count="$(wc -l < "$differ" | tr -d ' ')"
  error_count="$(wc -l < "$errors" | tr -d ' ')"

  printf 'Check result: missing=%s, different_size=%s, errors=%s\n' \
    "$missing_count" "$differ_count" "$error_count"

  if (( rc == 0 )); then
    return 0
  fi

  preview_report "$missing" "missing on Google Drive"
  preview_report "$differ" "different size"
  preview_report "$errors" "check errors"
  return "$rc"
}

[[ -f "$CONFIG" ]] || die "Missing rclone.conf: $CONFIG"
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

printf '\nFresh migration target: %s\n' "$DESTINATION"
printf 'Press Ctrl+C to cancel.\n\n'

"$RCLONE" copy "$SOURCE" "$DESTINATION" \
  --config "$CONFIG" \
  --size-only \
  --transfers 4 \
  --checkers 8 \
  --create-empty-src-dirs \
  --stats 10s \
  --stats-one-line-date

printf '\nCopy finished. Verifying...\n'
if verify; then
  printf '\nCOMPLETE: migration finished and verification passed.\n'
  exit 0
fi

die "Final verification failed. Reports are in $REPORT_DIR."
