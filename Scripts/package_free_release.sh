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

# Optional overrides for subsequent releases; the project defaults are used otherwise.
version_args=(ENABLE_HARDENED_RUNTIME=NO)
if [[ -n "${RELEASE_VERSION:-}" ]]; then version_args+=("MARKETING_VERSION=$RELEASE_VERSION"); fi
if [[ -n "${RELEASE_BUILD:-}" ]]; then version_args+=("CURRENT_PROJECT_VERSION=$RELEASE_BUILD"); fi

xcodebuild -project DynamicIslandV2.xcodeproj -scheme DynamicIslandV2 \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$build_dir" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  "${version_args[@]}" build > "$package_dir/build.log" 2>&1 || {
    tail -n 60 "$package_dir/build.log"
    exit 1
  }

app="$package_dir/Dynamic Island.app"
ditto "$build_dir/Build/Products/Release/Dynamic Island.app" "$app"
/usr/bin/codesign --verify --deep --strict "$app"
python3 Scripts/verify_release.py "$app"
cp Scripts/LEGGIMI.txt "$package_dir/LEGGIMI.txt"
# Resource forks and bundle symlinks survive delivery by mail, AirDrop or cloud storage.
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$package_dir/Dynamic-Island.zip"
/usr/bin/zip -q -j "$package_dir/Dynamic-Island.zip" "$package_dir/LEGGIMI.txt"

sparkle_bin="$build_dir/SourcePackages/artifacts/sparkle/Sparkle/bin"
account=com.thierrypiazza.DynamicIslandV2
public_key="$("$sparkle_bin/generate_keys" --account "$account" -p)"
embedded_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$app/Contents/Info.plist")"
if [[ "$public_key" != "$embedded_key" ]]; then
  printf 'Errore: la chiave nel Portachiavi non corrisponde alla chiave pubblica dell’app.\n' >&2
  exit 1
fi
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+)*$ || ! "$build" =~ ^[0-9]+$ ]]; then
  printf 'Usa una versione numerica (es. 1.2) e un numero di build intero crescente.\n' >&2
  exit 1
fi
tag="v$version-build$build"
if [[ -n "${RELEASE_NOTES_FILE:-}" ]]; then
  cp "$RELEASE_NOTES_FILE" "$package_dir/Dynamic Island.md"
fi
"$sparkle_bin/generate_appcast" --account "$account" --maximum-deltas 0 \
  --download-url-prefix "https://github.com/ThierryPiazza/DynamicIslandMacV2/releases/download/$tag/" \
  --embed-release-notes "$package_dir"
python3 Scripts/verify_appcast.py "$package_dir"
python3 - "$package_dir" "$version" "$build" "$tag" <<'PY'
import json, pathlib, sys
path, version, build, tag = sys.argv[1:]
(pathlib.Path(path) / 'release.json').write_text(json.dumps({
    'repository': 'ThierryPiazza/DynamicIslandMacV2',
    'version': version, 'build': int(build), 'tag': tag,
}, indent=2) + '\n')
PY
(cd "$package_dir" && /usr/bin/shasum -a 256 'Dynamic-Island.zip' appcast.xml > SHA256.txt)
printf '\nPacchetto pronto: %s\n' "$package_dir/Dynamic-Island.zip"
printf 'Catalogo con firma dell’aggiornamento: %s/appcast.xml\n' "$package_dir"
printf 'Pubblica con: Scripts/publish_update.sh "%s"\n' "$package_dir"
printf 'Requisiti: macOS 14.6+, Intel o Apple Silicon. Firma ad hoc, non notarizzata.\n'
