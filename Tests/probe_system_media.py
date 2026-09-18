"""Read-only smoke check of the helper embedded in a built DynamicIsland app."""
import argparse
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("app_path", type=Path)
args = parser.parse_args()
contents = args.app_path / "Contents"
script = contents / "Resources/MediaRemoteAdapter_MediaRemoteAdapter.bundle/Contents/Resources/run.pl"
library = contents / "Frameworks/MediaRemoteAdapter.framework/MediaRemoteAdapter"
if not script.is_file() or not library.is_file():
    raise SystemExit("Missing embedded media helper")
result = subprocess.run(["/usr/bin/perl", str(script), str(library), "get"],
                        capture_output=True, text=True, timeout=8)
print("Helper exit:", result.returncode)
if result.stderr:
    print(result.stderr[:600])
for line in result.stdout.splitlines():
    if line == "NIL":
        print("Valid response: no system media")
        continue
    payload = json.loads(line)["payload"]
    print(json.dumps({"source": payload.get("bundleIdentifier"),
                      "playing": payload.get("isPlaying"),
                      "has_title": bool(payload.get("title")),
                      "has_artwork": bool(payload.get("artworkDataBase64")),
                      "has_duration": bool(payload.get("durationMicros"))}))
if not result.stdout:
    raise SystemExit("No response from MediaRemote")
raise SystemExit(result.returncode)
