#!/usr/bin/env bash
# Build sing-box 1.12 libbox.aar and drop it into android/app/libs/.
# This script does not download or compile anything by itself. Run it on a
# machine with Go, the Android SDK, and gomobile.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${SINGBOX_VERSION:-v1.12.25}"
WORK="${TMPDIR:-/tmp}/nukefy-libbox"

echo "Nukefy VPN expects sing-box ${VERSION} experimental/libbox."
echo "Android TUN mode is compiled only when android/app/libs/libbox.aar exists."
echo "Without the AAR the app still builds and can use a local SOCKS/HTTP proxy"
echo "if the device allows executing a downloaded sing-box binary."
echo

if ! command -v go >/dev/null 2>&1; then
  echo "Go is not installed. Install Go 1.24+ and rerun."
  exit 1
fi

mkdir -p "$WORK"
cd "$WORK"
if [ ! -d sing-box ]; then
  git clone --depth 1 --branch "$VERSION" https://github.com/SagerNet/sing-box.git
fi
cd sing-box
go install golang.org/x/mobile/cmd/gomobile@latest
export PATH="$(go env GOPATH)/bin:$PATH"
gomobile init
# androidapi 21 matches the app minSdk. If the bind fails, retry with 24.
gomobile bind -target android -androidapi 21 -o "$ROOT/android/app/libs/libbox.aar" ./experimental/libbox
echo "Wrote $ROOT/android/app/libs/libbox.aar"
echo "Rebuild with: flutter build apk --release"
