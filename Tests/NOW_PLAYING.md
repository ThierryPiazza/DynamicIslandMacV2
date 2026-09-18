# Now Playing checks

The app prefers the macOS Now Playing source (including paused media). When no
valid system source is available it uses native player notifications and then
browser media detection. System metadata availability depends on the player and
macOS; the status appears in Settings. Turning generic reading off exercises the
fallback. Browser fallback supports scriptable Chromium browsers and Safari,
with Automation/JavaScript from Apple Events enabled by the user. Firefox can be
reported by system Now Playing but has no AppleScript DOM fallback. Cross-origin
iframes and closed shadow roots are not inspected. Browser fallback offers direct
play/pause only when an HTML media element is available; it does not invent
previous/next handlers. Native fallback controls target Music/Spotify directly.

## Deterministic checks

From the project root:

```sh
swiftc DynamicIslandV2/System/BrowserObserver.swift Tests/BrowserMediaChecks.swift -o /tmp/browser-media-checks
/tmp/browser-media-checks
swiftc DynamicIslandV2/Core/CompactActivity.swift Tests/CompactActivityChecks.swift -o /tmp/compact-activity-checks
/tmp/compact-activity-checks
```

## Read-only system probe

After building, pass the built `.app` to `Tests/probe_system_media.py`.
It verifies the embedded script and dynamic framework, then prints only source
identity, playing state and metadata-presence flags, never the media title.
Run outside an execution sandbox to reach the user's MediaRemote service.
`NIL` means no system media; it is not proof that every player is supported.

`MediaAdapterChecks.swift` links against the built MediaRemoteAdapter framework
and verifies initial snapshot, stop, no commands after stop, and restart.
It does not change playback. Arc was successfully detected with title, artwork,
duration and active playback on the development Mac.

## Interactive checks

- Start/pause/resume media in Arc; verify elapsed time and artwork in the notch.
- Play from a second app, verify the displayed system source changes.
- Close the active player; ensure its stale title disappears.
- Disable generic reading, test two browsers with one paused and one playing.
- In fallback mode, navigate/close the selected tab before clicking play/pause:
  no different page should receive that command.
- Disable Now Playing while a browser query is running: late results must be ignored.

The vendored dependency and upstream revision are documented in
`Packages/MediaRemoteAdapter/UPSTREAM.md`; license notices ship in the app.
