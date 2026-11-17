#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d /tmp/dynamicisland-zen-tests.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -module-cache-path "$test_dir/cache" DynamicIslandV2/System/ZenMediaSnapshot.swift Scripts/ZenBridge/main.swift -o "$test_dir/host"
xcrun swiftc -module-cache-path "$test_dir/cache" Tests/ZenSelectionChecks.swift -o "$test_dir/selection" -parse-as-library
"$test_dir/selection"
xcrun swiftc -module-cache-path "$test_dir/cache" DynamicIslandV2/System/ZenMediaSnapshot.swift DynamicIslandV2/System/ZenMediaProvider.swift DynamicIslandV2/Modules/NowPlaying/NowPlayingInfo.swift DynamicIslandV2/Core/NSImage+Resize.swift Tests/ZenBridgeChecks.swift -o "$test_dir/bridge"
"$test_dir/bridge" "$test_dir/host" "$test_dir/state"
