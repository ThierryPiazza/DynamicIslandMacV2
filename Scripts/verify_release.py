"""Check the actual distributable bundle, without reading personal data."""
import pathlib
import plistlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1]).resolve()
contents = app / "Contents"
with (contents / "Info.plist").open("rb") as stream:
    info = plistlib.load(stream)
executable = contents / "MacOS" / info["CFBundleExecutable"]
framework = contents / "Frameworks/MediaRemoteAdapter.framework/MediaRemoteAdapter"
resources = contents / "Resources"
required = [executable, framework, resources / "BrowserMedia.js",
            resources / "ThirdPartyNotices.txt",
            resources / "MediaRemoteAdapter_MediaRemoteAdapter.bundle/Contents/Resources/run.pl"]
for file in required:
    if not file.is_file():
        raise SystemExit(f"Risorsa mancante: {file}")
for binary in [executable, framework]:
    arches = subprocess.check_output(["/usr/bin/lipo", "-archs", str(binary)], text=True).split()
    if set(arches) != {"arm64", "x86_64"}:
        raise SystemExit(f"Architetture incomplete: {binary.name}: {arches}")
    linkage = subprocess.check_output(["/usr/bin/otool", "-L", str(binary)], text=True)
    for line in linkage.splitlines():
        if not line.startswith("\t"):
            continue
        dependency = line.strip().split(" (", 1)[0]
        if not dependency.startswith(("@rpath/", "@loader_path/", "@executable_path/", "/System/Library/", "/usr/lib/")):
            raise SystemExit(f"Dipendenza esterna non distribuibile: {dependency}")
subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)
print(f"PASS: app universale, risorse incluse, dipendenze di sistema/bundle, firma valida. macOS minimo: {info.get('LSMinimumSystemVersion')}")
