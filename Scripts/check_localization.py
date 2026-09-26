#!/usr/bin/env python3
"""Her arayüz metninin İngilizce çevirisi var mı, biçim belirteçleri tutuyor mu?

Anahtarları elle toplamak yerine derleyiciye çıkartıyoruz
(-emit-localized-strings): SwiftUI metinleri ve String(localized:) çağrıları
tam olarak çalışma anında aranacak anahtarlarla gelir. Çevirisi olmayan bir
metin ekranda sessizce Türkçe kalacağı için bunu CI'da hata sayıyoruz.

Kullanım:  python3 Scripts/check_localization.py
"""
import glob
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EN_STRINGS = os.path.join(ROOT, "Resources/en.lproj/Localizable.strings")
SETTINGS = os.path.join(ROOT, "Sources/MacGuard/Core/Settings.swift")
SPEC = re.compile(r"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:ll|l|h)?[@dDuUxXoOfeEgGcCsSpaA]")


def specifiers(text: str) -> list:
    return sorted(SPEC.findall(text.replace("%%", "")))


def extracted_keys(work: str) -> dict:
    out = os.path.join(work, "strings")
    cmd = ["swift", "build", "--package-path", ROOT, "--build-path", os.path.join(work, "build"),
           "-Xswiftc", "-emit-localized-strings", "-Xswiftc", "-emit-localized-strings-path",
           "-Xswiftc", out]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stdout[-4000:] + result.stderr[-4000:])
        sys.exit("✗ Derleme başarısız; anahtarlar çıkarılamadı.")
    keys = {}
    for path in glob.glob(os.path.join(out, "*.stringsdata")):
        data = json.load(open(path, encoding="utf-8"))
        source = os.path.relpath(data["source"], ROOT)
        for table in data.get("tables", {}).values():
            for entry in table:
                line = entry["location"]["startingLine"]
                keys.setdefault(entry["key"], f"{source}:{line}")
    return keys


def default_text_keys() -> dict:
    """Settings'teki varsayılan metinler değişkenden aranıyor; derleyici görmez."""
    source = open(SETTINGS, encoding="utf-8").read()
    keys = {}
    for match in re.finditer(r'static let default\w+Key = "((?:[^"\\]|\\.)*)"', source):
        keys[match.group(1).encode().decode("unicode_escape").encode("latin-1").decode("utf-8")] = \
            "Sources/MacGuard/Core/Settings.swift"
    return keys


def english_table() -> dict:
    raw = subprocess.run(["plutil", "-convert", "json", "-o", "-", EN_STRINGS],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(raw)


def main() -> int:
    with tempfile.TemporaryDirectory() as work:
        keys = extracted_keys(work)
    keys.update(default_text_keys())
    english = english_table()

    missing = {k: loc for k, loc in keys.items() if k not in english}
    mismatched = {k: english[k] for k in keys
                  if k in english and specifiers(k) != specifiers(english[k])}
    unused = sorted(k for k in english if k not in keys)

    for key, loc in sorted(missing.items(), key=lambda kv: kv[1]):
        print(f"✗ çeviri yok   {loc}: {key!r}")
    for key, value in mismatched.items():
        print(f"✗ belirteç     {key!r} → {value!r}")
    for key in unused:
        print(f"! kullanılmıyor {key!r}")

    print(f"{len(keys)} anahtar · {len(missing)} eksik · {len(mismatched)} belirteç hatası · "
          f"{len(unused)} kullanılmayan")
    return 1 if missing or mismatched else 0


if __name__ == "__main__":
    sys.exit(main())
