#!/usr/bin/env python3
"""Prüft die Lokalisierung (Localizable.xcstrings) gegen den Swift-Quelltext.

Findet alle übersetzbaren Schlüssel:
  - NSLocalizedString("…", …) im Kern und in der Oberfläche
  - String-Literale in SwiftUI-APIs, die automatisch LocalizedStringKey sind
    (Text, Label, Button, Toggle, Picker, …)

Fehler:
  - Schlüssel ohne Eintrag im Katalog oder ohne Übersetzung in einer Sprache
  - Katalogeinträge, die im Quelltext nicht mehr vorkommen (veraltet)
  - Platzhalter (%@, %1$@ …) passen in einer Übersetzung nicht zum Schlüssel
  - Interpolation "\\(…)" in einem übersetzbaren Literal (wird sonst nicht übersetzt)

Aufruf: python3 Tools/l10n/check_strings.py [--root .]  (Exit-Code 1 bei Fehlern)
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

LANGUAGES = ("de", "tr")
SOURCE_DIR = "QuranRecitationFinder"
CATALOG = "QuranRecitationFinder/Localizable.xcstrings"
INFOPLIST_CATALOG = "QuranRecitationFinder/InfoPlist.xcstrings"
INFOPLIST_KEYS = ("NSMicrophoneUsageDescription",)

# Swift-String-Literal ohne mehrzeilige Strings: "…" mit Escapes
_LIT = r'"((?:[^"\\\n]|\\.)*)"'
SWIFTUI_APIS = ("Text", "Label", "Button", "Toggle", "Picker", "LabeledContent", "NavigationLink",
                "ProgressView", "DisclosureGroup", "ContentUnavailableView", "TextField", "Stepper",
                "Section", "Link")
MODIFIERS = ("navigationTitle", "alert", "confirmationDialog", "accessibilityLabel", "accessibilityHint")

NSLOC_RE = re.compile(r'NSLocalizedString\(\s*' + _LIT)
# Text("…") – das erste Argument ist ein Literal; Text(verbatim:) beginnt mit "verbatim:" und passt nicht.
API_RE = re.compile(r'(?<![\w.])(?:' + "|".join(SWIFTUI_APIS) + r')\(\s*' + _LIT)
MOD_RE = re.compile(r'\.(?:' + "|".join(MODIFIERS) + r')\(\s*' + _LIT)
# accessibilityLabel(bedingung ? "a" : "b") – Literale in einem ternären Ausdruck sind String, nicht Key
TERNARY_RE = re.compile(r'\.(?:' + "|".join(MODIFIERS) + r')\([^")\n]*\?\s*"')
PLACEHOLDER_RE = re.compile(r'%(?:\d+\$)?[@dfs]|%%')


def unescape(literal: str) -> str:
    return (literal.replace('\\"', '"').replace("\\n", "\n").replace("\\t", "\t").replace("\\\\", "\\"))


def strip_comments(source: str) -> str:
    """Entfernt //-Kommentare (außerhalb von Strings) und /* */-Blöcke."""
    out, i, n = [], 0, len(source)
    in_str = False
    while i < n:
        c = source[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(source[i + 1]); i += 2; continue
            if c == '"' or c == "\n":
                in_str = False
            i += 1
        elif c == '"':
            in_str = True; out.append(c); i += 1
        elif source.startswith("//", i):
            j = source.find("\n", i)
            i = n if j < 0 else j
        elif source.startswith("/*", i):
            j = source.find("*/", i + 2)
            i = n if j < 0 else j + 2
        else:
            out.append(c); i += 1
    return "".join(out)


def extract(source: str, filename: str = "") -> tuple[set[str], list[str]]:
    """Liefert (Schlüssel, Probleme) für eine Swift-Datei."""
    text = strip_comments(source)
    keys: set[str] = set()
    problems: list[str] = []
    for lineno, line in enumerate(text.splitlines(), 1):
        where = f"{filename}:{lineno}"
        if TERNARY_RE.search(line):
            problems.append(f"{where}: ternärer Ausdruck mit Literalen – wird nicht übersetzt, Text(\"…\") je Zweig verwenden")
        for regex, is_ui in ((NSLOC_RE, False), (API_RE, True), (MOD_RE, True)):
            for m in regex.finditer(line):
                raw = m.group(1)
                if "\\(" in raw:
                    if is_ui or regex is NSLOC_RE:
                        problems.append(f"{where}: Interpolation in übersetzbarem Literal: \"{raw}\"")
                    continue
                key = unescape(raw)
                if not key.strip() or not re.search(r"[A-Za-z]", key):
                    continue  # nur Symbole/Ziffern – nichts zu übersetzen
                keys.add(key)
    return keys, problems


def placeholders(s: str) -> list[str]:
    found = [p for p in PLACEHOLDER_RE.findall(s) if p != "%%"]
    # Positionsangaben normalisieren: %@ an Stelle i == %i$@
    normalized = []
    for i, p in enumerate(found, 1):
        m = re.match(r"%(\d+)\$(.)", p)
        normalized.append(f"{m.group(1)}{m.group(2)}" if m else f"{i}{p[-1]}")
    return sorted(normalized)


def check_catalog(catalog: dict, keys: set[str], required: tuple[str, ...] = LANGUAGES,
                  name: str = "Localizable") -> list[str]:
    problems = []
    if catalog.get("sourceLanguage") != "en":
        problems.append(f"{name}: sourceLanguage muss \"en\" sein")
    strings = catalog.get("strings", {})
    for key in sorted(keys):
        entry = strings.get(key)
        if entry is None:
            problems.append(f"{name}: Schlüssel fehlt im Katalog: \"{key}\"")
            continue
        locs = entry.get("localizations", {})
        for lang in required:
            unit = locs.get(lang, {}).get("stringUnit", {})
            value = unit.get("value", "")
            if not value.strip() or unit.get("state") not in ("translated", "needs_review"):
                problems.append(f"{name}: [{lang}] keine Übersetzung für \"{key}\"")
            elif placeholders(value) != placeholders(key):
                problems.append(f"{name}: [{lang}] Platzhalter passen nicht: \"{key}\" → \"{value}\"")
    for key in sorted(set(strings) - keys):
        if strings[key].get("extractionState") != "manual":
            problems.append(f"{name}: veralteter Eintrag (nicht im Quelltext): \"{key}\"")
    return problems


def collect(root: Path) -> tuple[set[str], list[str]]:
    keys: set[str] = set()
    problems: list[str] = []
    for path in sorted((root / SOURCE_DIR).rglob("*.swift")):
        k, p = extract(path.read_text(encoding="utf-8"), str(path.relative_to(root)))
        keys |= k
        problems += p
    return keys, problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--list", action="store_true", help="nur gefundene Schlüssel ausgeben")
    args = parser.parse_args(argv)

    keys, problems = collect(args.root)
    if args.list:
        for key in sorted(keys):
            print(json.dumps(key, ensure_ascii=False))
        return 0
    catalog_path = args.root / CATALOG
    if not catalog_path.exists():
        problems.append(f"{CATALOG} fehlt")
    else:
        problems += check_catalog(json.loads(catalog_path.read_text(encoding="utf-8")), keys)
    plist_path = args.root / INFOPLIST_CATALOG
    if not plist_path.exists():
        problems.append(f"{INFOPLIST_CATALOG} fehlt")
    else:
        problems += check_catalog(json.loads(plist_path.read_text(encoding="utf-8")), set(INFOPLIST_KEYS),
                                  required=("en",) + LANGUAGES, name="InfoPlist")

    for p in problems:
        print("FEHLER:", p)
    print(f"{len(keys)} Schlüssel, Sprachen: en (Quelle), {', '.join(LANGUAGES)} – "
          f"{'OK' if not problems else f'{len(problems)} Problem(e)'}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
