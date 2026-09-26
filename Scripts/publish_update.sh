#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 Scripts/publish_update.py "$@"
