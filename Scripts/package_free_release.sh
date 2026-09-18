#!/bin/bash
# Creates a self-contained universal macOS app. No Apple account is used.
set -euo pipefail
cd "$(dirname "$0")/.."
project_root="$PWD"
release_root="${1:-$project_root/dist}"
mkdir -p "$release_root"
release_root="$(cd "$release_root" && pwd)"
package_dir="$(mktemp -d "$release_root/Dynamic Island-XXXXXX")"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/dynamicisland-release.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

xcodebuild -project DynamicIslandV2.xcodeproj -scheme DynamicIslandV2 \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$build_dir" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  ENABLE_HARDENED_RUNTIME=NO build > "$package_dir/build.log" 2>&1

app="$package_dir/Dynamic Island.app"
ditto "$build_dir/Build/Products/Release/Dynamic Island.app" "$app"
/usr/bin/codesign --verify --deep --strict "$app"
python3 Scripts/verify_release.py "$app"
cp Scripts/LEGGIMI.txt "$package_dir/LEGGIMI.txt"
# Resource forks and bundle symlinks survive delivery by mail, AirDrop or cloud storage.
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$package_dir/Dynamic Island.zip"
/usr/bin/zip -q -j "$package_dir/Dynamic Island.zip" "$package_dir/LEGGIMI.txt"
/usr/bin/shasum -a 256 "$package_dir/Dynamic Island.zip" > "$package_dir/SHA256.txt"
printf '\nPacchetto pronto: %s\n' "$package_dir/Dynamic Island.zip"
printf 'Requisiti: macOS 14.6+, Intel o Apple Silicon. Firma ad hoc, non notarizzata.\n'
