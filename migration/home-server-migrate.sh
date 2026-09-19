#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE="onedrive-src:"
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${1:-$ROOT/rclone.conf}"
DESTINATION_FOLDER="${2:-OneDrive Migration 2}"
DESTINATION="gdrive-dst:${DESTINATION_FOLDER}"
RCLONE="$ROOT/bin/rclone"
REPORT_DIR="$ROOT/reports"
TPS_ARGS=(--tpslimit 8 --tpslimit-burst 1)
COPY_LOG="$REPORT_DIR/copy.log"
MALWARE_FILE="$REPORT_DIR/malware-skipped.txt"

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

extract_malware_paths() {
  : > "$MALWARE_FILE"
  [[ -f "$COPY_LOG" ]] || return 0

  sed -nE 's/^.*ERROR : (.*): Failed to copy: .*infected with a virus.*$/\1/p' "$COPY_LOG" |
    sort -u > "$MALWARE_FILE"

  local count
  count="$(wc -l < "$MALWARE_FILE" | tr -d ' ')"
  if (( count > 0 )); then
    printf '\nSkipping %s file(s) blocked by OneDrive malware detection:\n' "$count"
    sed -n '1,30p' "$MALWARE_FILE"
    if (( count > 30 )); then
      printf '...\n'
    fi
  fi
}

verify() {
  local missing="$REPORT_DIR/final-missing-on-dst.txt"
  local differ="$REPORT_DIR/final-different.txt"
  local errors="$REPORT_DIR/final-errors.txt"
  local missing_sorted="$REPORT_DIR/final-missing.sorted.txt"
  local malware_sorted="$REPORT_DIR/malware-skipped.sorted.txt"
  local unexpected_missing="$REPORT_DIR/final-unexpected-missing.txt"
  local skipped_confirmed="$REPORT_DIR/final-malware-skipped.txt"

  rm -f "$missing" "$differ" "$errors" "$missing_sorted" "$malware_sorted" "$unexpected_missing" "$skipped_confirmed"

  set +e
  "$RCLONE" check "$SOURCE" "$DESTINATION" \
    --config "$CONFIG" \
    --one-way \
    --size-only \
    --missing-on-dst "$missing" \
    --differ "$differ" \
    --error "$errors" \
    --checkers 8 \
    "${TPS_ARGS[@]}" \
    --stats 30s \
    --stats-one-line-date
  local check_rc=$?
  set -e

  touch "$missing" "$differ" "$errors" "$MALWARE_FILE"
  sort -u "$missing" > "$missing_sorted"
  sort -u "$MALWARE_FILE" > "$malware_sorted"
  comm -23 "$missing_sorted" "$malware_sorted" > "$unexpected_missing"
  comm -12 "$missing_sorted" "$malware_sorted" > "$skipped_confirmed"

  local missing_count differ_count error_count unexpected_count skipped_count
  missing_count="$(wc -l < "$missing_sorted" | tr -d ' ')"
  differ_count="$(wc -l < "$differ" | tr -d ' ')"
  error_count="$(wc -l < "$errors" | tr -d ' ')"
  unexpected_count="$(wc -l < "$unexpected_missing" | tr -d ' ')"
  skipped_count="$(wc -l < "$skipped_confirmed" | tr -d ' ')"

  printf 'Check result: missing=%s, different_size=%s, errors=%s, malware_skipped=%s\n' \
    "$missing_count" "$differ_count" "$error_count" "$skipped_count"

  if (( differ_count == 0 && error_count == 0 && unexpected_count == 0 )); then
    if (( skipped_count > 0 )); then
      printf 'All transferable files verified. %s OneDrive malware-flagged file(s) were intentionally skipped.\n' "$skipped_count"
    fi
    return 0
  fi

  preview_report "$unexpected_missing" "unexpected missing on Google Drive"
  preview_report "$differ" "different size"
  preview_report "$errors" "check errors"
  return "$check_rc"
}

[[ -f "$CONFIG" ]] || die "Missing rclone.conf: $CONFIG"
chmod 600 "$CONFIG"
mkdir -p "$REPORT_DIR"
: > "$MALWARE_FILE"

if [[ ! -x "$RCLONE" ]]; then
  install_rclone
fi

printf 'Using: '
"$RCLONE" version | head -n 1

remotes="$("$RCLONE" listremotes --config "$CONFIG")"
grep -Fxq 'onedrive-src:' <<<"$remotes" || die "rclone.conf is missing remote 'onedrive-src:'."
grep -Fxq 'gdrive-dst:' <<<"$remotes" || die "rclone.conf is missing remote 'gdrive-dst:'."

drive_config="$("$RCLONE" config show gdrive-dst --config "$CONFIG")"
grep -Eq '^client_id = .+' <<<"$drive_config" ||
  die "gdrive-dst still uses rclone's shared Google client. Run update-google-client.ps1 on Windows first."

printf '\nValidating OneDrive access...\n'
"$RCLONE" lsf "$SOURCE" --config "$CONFIG" --max-depth 1 "${TPS_ARGS[@]}" >/dev/null
printf 'Validating Google Drive access...\n'
"$RCLONE" lsf "gdrive-dst:" --config "$CONFIG" --max-depth 1 "${TPS_ARGS[@]}" >/dev/null

printf '\nMigration target: %s\n' "$DESTINATION"
printf 'Existing matching files are skipped. OneDrive malware-flagged files are skipped without override.\n'
printf 'Press Ctrl+C to cancel.\n\n'

set +e
"$RCLONE" copy "$SOURCE" "$DESTINATION" \
  --config "$CONFIG" \
  --size-only \
  --transfers 4 \
  --checkers 8 \
  --retries 1 \
  "${TPS_ARGS[@]}" \
  --create-empty-src-dirs \
  --stats 10s \
  --stats-one-line-date 2>&1 | tee "$COPY_LOG"
copy_rc=${PIPESTATUS[0]}
set -e

extract_malware_paths

if (( copy_rc != 0 )); then
  printf '\nCopy returned exit code %s. Verification will determine whether only malware-blocked files were skipped.\n' "$copy_rc"
fi

printf '\nCopy pass finished. Verifying...\n'
if verify; then
  printf '\nCOMPLETE: migration verification passed for all transferable files.\n'
  exit 0
fi

die "Final verification failed. See $REPORT_DIR for details."
