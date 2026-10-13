"""Phase 1 – App-Ressourcen erzeugen: Korantext, Metadaten, Übersetzungen.

Lädt alles herunter, prüft es auf Vollständigkeit und legt es in
QuranRecitationFinder/Resources/ ab. Die Inhalte bleiben unverändert
(Lizenzbedingungen Tanzil + QuranEnc), nur das Dateiformat der
Übersetzungen wird zu einer JSON-Datei je Übersetzung zusammengefasst.

Aufruf:   python build_resources.py
          python build_resources.py --list tr      (verfügbare türkische Übersetzungen)
          python build_resources.py --tr turkish_shaban
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[2]
RESOURCES = ROOT / "QuranRecitationFinder" / "Resources"
QURAN_DIR = RESOURCES / "Quran"
TRANSLATION_DIR = RESOURCES / "Translations"

VERSE_COUNT = 6236
SURA_COUNT = 114

TANZIL_TEXT_URL = (
    "https://tanzil.net/pub/download/index.php?marks=true&sajdah=true&rub=false"
    "&tatweel=true&quranType={edition}&outType=xml&agree=true"
)
TANZIL_METADATA_URL = "https://tanzil.net/res/text/metadata/quran-data.xml"
TANZIL_EDITIONS = {
    "uthmani": "Anzeige (Uthmani-Schrift)",
    "simple-clean": "Vergleich in der Verssuche",
}

QURANENC_API = "https://quranenc.com/api/v1"
# Bevorzugte Übersetzungen je Sprache – erste verfügbare wird genommen.
# Mit --list <sprache> lassen sich alle Optionen anzeigen.
PREFERRED = {
    "de": ["german_bubenheim"],
    "tr": ["turkish_rwwad", "turkish_shaban"],
    "en": ["english_saheeh"],
}

session = requests.Session()
session.headers["User-Agent"] = "QuranRecitationFinder-build/1.0"


def get(url: str, retries: int = 4) -> bytes:
    last_error = None
    for attempt in range(retries):
        try:
            r = session.get(url, timeout=30)
            if r.status_code == 200:
                return r.content
            last_error = f"HTTP {r.status_code}"
            if r.status_code == 404:
                break
        except requests.RequestException as e:
            last_error = str(e)
        time.sleep(2**attempt)
    raise RuntimeError(f"Download fehlgeschlagen ({last_error}): {url}")


# -- Tanzil ---------------------------------------------------------------


def count_ayas(xml_bytes: bytes) -> tuple[int, int]:
    root = ET.fromstring(xml_bytes)
    suras = list(root.iter("sura"))
    return len(suras), sum(1 for s in suras for _ in s.iter("aya"))


def fetch_tanzil() -> list[dict]:
    QURAN_DIR.mkdir(parents=True, exist_ok=True)
    sources = []
    for edition, purpose in TANZIL_EDITIONS.items():
        content = get(TANZIL_TEXT_URL.format(edition=edition))
        suras, ayas = count_ayas(content)
        if (suras, ayas) != (SURA_COUNT, VERSE_COUNT):
            raise RuntimeError(f"Tanzil {edition}: {suras} Suren / {ayas} Verse – erwartet 114 / 6236")
        (QURAN_DIR / f"quran-{edition}.xml").write_bytes(content)  # unverändert
        print(f"✓ Tanzil {edition}: {ayas} Verse")
        sources.append({"file": f"quran-{edition}.xml", "edition": edition, "purpose": purpose})

    meta = get(TANZIL_METADATA_URL)
    root = ET.fromstring(meta)
    suras = list(root.find("suras").iter("sura"))
    total = sum(int(s.get("ayas")) for s in suras)
    if len(suras) != SURA_COUNT or total != VERSE_COUNT:
        raise RuntimeError(f"Tanzil-Metadaten unvollständig: {len(suras)} Suren / {total} Verse")
    (QURAN_DIR / "quran-data.xml").write_bytes(meta)
    print("✓ Tanzil-Metadaten: 114 Suren")
    sources.append({"file": "quran-data.xml", "edition": "metadata", "purpose": "Surennamen, Versanzahl"})
    return sources


# -- QuranEnc -------------------------------------------------------------


def list_translations(language: str) -> list[dict]:
    data = json.loads(get(f"{QURANENC_API}/translations/list/{language}"))
    items = data.get("translations", data) if isinstance(data, dict) else data
    return [t for t in items if t.get("language_iso_code", language) == language]


def choose_translation(language: str, override: str | None) -> dict:
    available = list_translations(language)
    by_key = {t["key"]: t for t in available}
    for key in ([override] if override else PREFERRED[language]):
        if key in by_key:
            return by_key[key]
    options = "\n".join(f"   {t['key']:28} {t.get('title', '')}" for t in available)
    raise RuntimeError(
        f"Keine der gewünschten Übersetzungen für '{language}' gefunden.\nVerfügbar:\n{options}\n"
        f"→ mit --{language} <key> auswählen"
    )


def fetch_translation(meta: dict, verses_per_sura: list[int]) -> dict:
    key = meta["key"]
    verses = []
    for sura in range(1, SURA_COUNT + 1):
        data = json.loads(get(f"{QURANENC_API}/translation/sura/{key}/{sura}"))
        rows = data["result"] if isinstance(data, dict) else data
        rows = sorted(rows, key=lambda r: int(r["aya"]))
        if len(rows) != verses_per_sura[sura - 1]:
            raise RuntimeError(f"{key} Sure {sura}: {len(rows)} Verse, erwartet {verses_per_sura[sura - 1]}")
        for r in rows:
            text = (r.get("translation") or "").strip()
            if not text:
                raise RuntimeError(f"{key} {sura}:{r['aya']}: leere Übersetzung")
            verses.append(
                {
                    "sura": int(r["sura"]),
                    "aya": int(r["aya"]),
                    "text": r["translation"],  # unverändert (QuranEnc-Bedingung)
                    "footnotes": r.get("footnotes") or None,
                }
            )
        print(f"\r  {key}: Sure {sura}/114", end="", flush=True)
        time.sleep(0.15)  # Server schonen
    print()
    return {
        "key": key,
        "language": meta.get("language_iso_code"),
        "title": meta.get("title", key),
        "version": str(meta.get("version", "")),
        "lastUpdate": meta.get("last_update"),
        "direction": meta.get("direction", "ltr"),
        "source": "QuranEnc.com",
        "sourceURL": f"https://quranenc.com/en/browse/{key}",
        "verses": verses,
    }


def verses_per_sura_from_metadata() -> list[int]:
    root = ET.parse(QURAN_DIR / "quran-data.xml").getroot()
    return [int(s.get("ayas")) for s in root.find("suras").iter("sura")]


def write_sources(tanzil: list[dict], translations: list[dict]) -> None:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    lines = [
        "# Quellen und Lizenzen der App-Daten",
        "",
        f"Erzeugt mit `Tools/data/build_resources.py` am {now}. Inhalte unverändert übernommen.",
        "",
        "## Korantext – Tanzil.net",
        "",
        "Lizenz: Creative Commons Attribution 3.0. Unveränderte Kopie, Quelle Tanzil.net mit Link",
        "https://tanzil.net muss in der App sichtbar genannt werden.",
        "",
        "| Datei | Zweck |",
        "|---|---|",
    ]
    lines += [f"| `Quran/{s['file']}` | {s['purpose']} |" for s in tanzil]
    lines += [
        "",
        "## Übersetzungen – QuranEnc.com",
        "",
        "Bedingungen: keine Änderung am Inhalt, QuranEnc.com als Quelle nennen, Versionsnummer angeben,",
        "auf neueste Version aktualisieren, Hinweise zur Übersetzung an QuranEnc melden,",
        "keine unpassende Werbung.",
        "",
        "| Datei | Sprache | Titel | Version |",
        "|---|---|---|---|",
    ]
    lines += [
        f"| `Translations/translation-{t['key']}.json` | {t['language']} | {t['title']} | {t['version']} |"
        for t in translations
    ]
    (RESOURCES / "SOURCES.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--list", metavar="SPRACHE", help="verfügbare Übersetzungen anzeigen (de/tr/en/...)")
    for lang in PREFERRED:
        p.add_argument(f"--{lang}", metavar="KEY", help=f"Übersetzung für {lang} festlegen")
    p.add_argument("--skip-tanzil", action="store_true", help="vorhandenen Korantext behalten")
    args = p.parse_args()

    if args.list:
        for t in list_translations(args.list):
            print(f"{t['key']:28} v{t.get('version', '?'):8} {t.get('title', '')}")
        return

    try:
        if args.skip_tanzil and (QURAN_DIR / "quran-data.xml").exists():
            tanzil = [{"file": f"quran-{e}.xml", "edition": e, "purpose": d} for e, d in TANZIL_EDITIONS.items()]
            tanzil.append({"file": "quran-data.xml", "edition": "metadata", "purpose": "Surennamen, Versanzahl"})
        else:
            tanzil = fetch_tanzil()
        per_sura = verses_per_sura_from_metadata()

        TRANSLATION_DIR.mkdir(parents=True, exist_ok=True)
        index = []
        for lang in PREFERRED:
            meta = choose_translation(lang, getattr(args, lang))
            print(f"→ {lang}: {meta['key']} (v{meta.get('version', '?')})")
            translation = fetch_translation(meta, per_sura)
            path = TRANSLATION_DIR / f"translation-{translation['key']}.json"
            path.write_text(json.dumps(translation, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
            entry = {k: translation[k] for k in ("key", "language", "title", "version", "direction", "source", "sourceURL")}
            entry["file"] = path.name
            index.append(entry)
            print(f"✓ {path.name} ({path.stat().st_size // 1024} KB)")

        (TRANSLATION_DIR / "translations-index.json").write_text(
            json.dumps({"translations": index}, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        write_sources(tanzil, index)
    except RuntimeError as e:
        sys.exit(f"✗ {e}")
    print(f"✓ Fertig. Ressourcen in {RESOURCES.relative_to(ROOT)}/ – bitte committen.")


if __name__ == "__main__":
    main()
