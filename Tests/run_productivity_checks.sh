#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swiftc -module-cache-path /tmp/DynamicIslandSwiftCache \
  DynamicIslandV2/Modules/Notes/NotesStore.swift \
  DynamicIslandV2/Modules/Notes/RemindersBridge.swift \
  DynamicIslandV2/Modules/Notes/ReminderTiming.swift \
  DynamicIslandV2/Modules/Clipboard/ClipboardMonitor.swift \
  DynamicIslandV2/Core/NSImage+Resize.swift \
  DynamicIslandV2/Core/OutputFile.swift \
  DynamicIslandV2/Modules/FileHub/ConversionOption.swift \
  DynamicIslandV2/Modules/FileHub/FileConverter.swift \
  DynamicIslandV2/Modules/FileHub/PDFConverter.swift \
  DynamicIslandV2/Modules/Shelf/ShelfFileActions.swift \
  DynamicIslandV2/Modules/Timer/PomodoroSession.swift \
  DynamicIslandV2/Core/ModuleSettings.swift \
  DynamicIslandV2/Core/NotchState.swift \
  DynamicIslandV2/Window/NotchGeometry.swift \
  DynamicIslandV2/App/LaunchAtLoginManager.swift \
  Tests/ProductivityChecks.swift -o /tmp/dynamicisland-productivity-checks
/tmp/dynamicisland-productivity-checks
swiftc -module-cache-path /tmp/DynamicIslandSwiftCache \
  DynamicIslandV2/Core/CompactActivity.swift Tests/CompactActivityChecks.swift -o /tmp/compact-activity-checks
/tmp/compact-activity-checks

swiftc -module-cache-path /tmp/DynamicIslandSwiftCache \
  DynamicIslandV2/Modules/Shelf/DocumentFileOperations.swift \
  Tests/DownloadOrganizerChecks.swift -o /tmp/dynamicisland-download-checks
/tmp/dynamicisland-download-checks

swiftc -module-cache-path /tmp/DynamicIslandSwiftCache \
  DynamicIslandV2/System/BrowserObserver.swift Tests/BrowserMediaChecks.swift -o /tmp/dynamicisland-browser-checks
/tmp/dynamicisland-browser-checks

swiftc -module-cache-path /tmp/DynamicIslandSwiftCache \
  DynamicIslandV2/Modules/NowPlaying/ArtworkFetcher.swift \
  DynamicIslandV2/Core/NSImage+Resize.swift Tests/ArtworkChecks.swift -o /tmp/dynamicisland-artwork-checks
/tmp/dynamicisland-artwork-checks
