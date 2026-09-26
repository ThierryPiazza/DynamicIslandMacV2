"""Verify the feed against the actual bundle and signed ZIP before publication."""
import pathlib
import plistlib
import subprocess
import sys
import urllib.parse
import xml.etree.ElementTree as ET


def verify(directory):
    directory = pathlib.Path(directory).resolve()
    plist = directory / "Dynamic Island.app/Contents/Info.plist"
    with plist.open("rb") as stream:
        info = plistlib.load(stream)
    archive = directory / "Dynamic-Island.zip"
    ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
    root = ET.parse(directory / "appcast.xml")
    items = root.findall("./channel/item")
    if len(items) != 1:
        raise ValueError("Il catalogo deve contenere esattamente questa release.")
    item = items[0]
    for field, key in (("version", "CFBundleVersion"),
                       ("shortVersionString", "CFBundleShortVersionString"),
                       ("minimumSystemVersion", "LSMinimumSystemVersion")):
        if item.findtext("sparkle:" + field, namespaces=ns) != info[key]:
            raise ValueError(f"Versione non coerente: {field}")
    enclosure = item.find("enclosure")
    tag = f"v{info['CFBundleShortVersionString']}-build{info['CFBundleVersion']}"
    expected = ("https://github.com/ThierryPiazza/DynamicIslandMacV2/releases/download/"
                + tag + "/" + urllib.parse.quote(archive.name))
    if enclosure is None or enclosure.get("url") != expected:
        raise ValueError("URL di download non coerente con la release.")
    if int(enclosure.get("length", "0")) != archive.stat().st_size:
        raise ValueError("Dimensione dell’archivio errata.")
    signature = enclosure.get("{" + ns["sparkle"] + "}edSignature")
    if not signature:
        raise ValueError("Firma EdDSA mancante.")
    subprocess.run(["/usr/bin/swift", str(pathlib.Path(__file__).with_name(
        "verify_update_signature.swift")), str(plist), str(archive), signature], check=True)
    print("PASS: catalogo, versioni, URL e archivio coerenti.")


if __name__ == "__main__":
    verify(sys.argv[1])
