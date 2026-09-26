"""Publish a verified update atomically: assets first, then make the draft public."""
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

from verify_appcast import verify


def gh(*args, check=True):
    result = subprocess.run(["gh", *map(str, args)], text=True, capture_output=True)
    if check and result.returncode:
        raise SystemExit(result.stderr)
    return result


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Uso: Scripts/publish_update.sh "dist/Dynamic Island-XXXXXX"')
    if not shutil.which("gh"):
        raise SystemExit("Installa GitHub CLI da https://cli.github.com e accedi con gh auth login, "
                         "oppure carica i file manualmente come descritto in Scripts/AGGIORNAMENTI.md.")
    directory = pathlib.Path(sys.argv[1]).resolve()
    verify(directory)
    manifest = json.loads((directory / "release.json").read_text())
    repo = "ThierryPiazza/DynamicIslandMacV2"
    if manifest["repository"] != repo:
        raise SystemExit("Repository inatteso.")
    with (directory / "Dynamic Island.app/Contents/Info.plist").open("rb") as stream:
        import plistlib
        info = plistlib.load(stream)
    tag = f"v{info['CFBundleShortVersionString']}-build{info['CFBundleVersion']}"
    if (manifest["tag"] != tag or manifest["version"] != info["CFBundleShortVersionString"]
            or manifest["build"] != int(info["CFBundleVersion"])):
        raise SystemExit("Metadati di pubblicazione incoerenti con l’app.")
    subprocess.run(["/usr/bin/shasum", "-a", "256", "-c", "SHA256.txt"], cwd=directory, check=True)
    repository = json.loads(gh("api", f"repos/{repo}").stdout)
    if repository["private"]:
        raise SystemExit("Le release devono essere pubbliche per essere scaricabili dall’app.")
    latest = gh("api", f"repos/{repo}/releases/latest", check=False)
    if latest.returncode and "404" not in latest.stderr:
        raise SystemExit(latest.stderr)
    if latest.returncode == 0:
        previous = json.loads(latest.stdout)
        with tempfile.TemporaryDirectory() as temp:
            gh("release", "download", previous["tag_name"], "--repo", repo,
               "--pattern", "appcast.xml", "--dir", temp)
            versions = ET.parse(pathlib.Path(temp) / "appcast.xml").findall(
                ".//{http://www.andymatuschak.org/xml-namespaces/sparkle}version")
            if not versions or any(int(v.text) >= manifest["build"] for v in versions):
                raise SystemExit("Incrementa RELEASE_BUILD rispetto alla versione già pubblicata.")
    existing = gh("release", "view", tag, "--repo", repo, "--json", "isDraft", check=False)
    if existing.returncode == 0:
        if not json.loads(existing.stdout)["isDraft"]:
            raise SystemExit("Questa versione è già pubblicata: crea una nuova build.")
    else:
        notes = directory / "Dynamic Island.md"
        if not notes.exists():
            notes = directory / "release-notes.md"
            notes.write_text(f"Dynamic Island {manifest['version']} (build {manifest['build']}).\n\n"
                             "Mac Intel e Apple Silicon, macOS 14.6 o successivo.\n"
                             "Scarica Dynamic-Island.zip e segui LEGGIMI.txt.\n"
                             "Aggiornamenti disponibili dal menu dell’app o da Impostazioni → Generali.\n"
                             "Build gratuita con firma ad hoc, non notarizzata.\n")
        gh("release", "create", tag, "--repo", repo, "--draft",
           "--title", f"Dynamic Island {manifest['version']}", "--notes-file", notes)
    for name in ("Dynamic-Island.zip", "appcast.xml", "SHA256.txt", "LEGGIMI.txt"):
        gh("release", "upload", tag, directory / name, "--repo", repo, "--clobber")
    gh("release", "edit", tag, "--repo", repo, "--draft=false", "--latest")
    print(f"Pubblicato: https://github.com/{repo}/releases/tag/{tag}")


if __name__ == "__main__":
    main()
