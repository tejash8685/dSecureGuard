#!/usr/bin/env bash
set -euo pipefail
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "iOS builds require macOS and Xcode." >&2
  exit 1
fi
cd "$(dirname "$0")/.."
symbols="artifacts/ios-symbols/$(date -u +%Y%m%d-%H%M%S)-$$"
mkdir -p "$symbols"
flutter pub get
flutter build ipa --release --obfuscate --split-debug-info="$symbols" \
  --dart-define="API_URL=${1:-http://192.168.1.110:8080/api}"
echo "IPA: build/ios/ipa; retain private symbols: $symbols"
