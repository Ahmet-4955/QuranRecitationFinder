"""Korantext laden (Tanzil XML oder TXT) und für den Vergleich normalisieren.

Die Tanzil-Dateien werden unverändert gespeichert (Lizenzbedingung);
die Normalisierung passiert nur im Arbeitsspeicher.
"""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

# Vokalzeichen, Koran-Pausenzeichen, hochgestelltes Alif, Tatweel usw.
_DIACRITICS = re.compile(
    "["
    "\u0610-\u061a"  # Ehrenzeichen / kleine Zeichen
    "\u064b-\u065f"  # Harakat, Tanwin, Shadda, Sukun
    "\u0670"  # hochgestelltes Alif
    "\u06d6-\u06ed"  # Koran-Annotationszeichen (Pausen, kleine Waw/Ya, ...)
    "\u0640"  # Tatweel
    "\u08d3-\u08ff"  # erweiterte Koranzeichen
    "]"
)
_CHAR_MAP = str.maketrans(
    {
        "\u0671": "\u0627",  # Alif Wasla -> Alif
        "\u0623": "\u0627",  # Alif mit Hamza oben
        "\u0625": "\u0627",  # Alif mit Hamza unten
        "\u0622": "\u0627",  # Alif Madda
        "\u0672": "\u0627",
        "\u0673": "\u0627",
        "\u0649": "\u064a",  # Alif Maqsura -> Ya
        "\u0629": "\u0647",  # Ta Marbuta -> Ha
        "\u0624": "\u0648",  # Waw mit Hamza -> Waw
        "\u0626": "\u064a",  # Ya mit Hamza -> Ya
        "\u06cc": "\u064a",  # Farsi Ya
        "\u06a9": "\u0643",  # Farsi Kaf
        "\u0621": "",  # freistehende Hamza (Uthmani: al-'akhira mit Hamza)
    }
)
_NON_ARABIC_LETTER = re.compile(r"[^\u0621-\u064a\s]")


def normalize(text: str) -> str:
    """Arabischen Text auf ein vergleichbares Grundgerüst reduzieren."""
    text = _DIACRITICS.sub("", text)
    text = text.translate(_CHAR_MAP)
    text = _NON_ARABIC_LETTER.sub(" ", text)
    return " ".join(text.split())


@dataclass(frozen=True)
class Verse:
    sura: int
    aya: int
    text: str

    @property
    def ref(self) -> str:
        return f"{self.sura}:{self.aya}"


class QuranCorpus:
    def __init__(self, verses: list[Verse], edition: str):
        if len(verses) != 6236:
            raise ValueError(f"Erwartet 6236 Verse, gefunden {len(verses)}")
        self.verses = verses
        self.edition = edition
        self._index = {(v.sura, v.aya): i for i, v in enumerate(verses)}

    def verse_index(self, sura: int, aya: int) -> int:
        return self._index[(sura, aya)]

    def verse_at(self, index: int) -> Verse:
        return self.verses[index]

    @classmethod
    def load(cls, path: str | Path, edition: str | None = None) -> "QuranCorpus":
        path = Path(path)
        edition = edition or path.stem
        if path.suffix.lower() == ".xml":
            return cls(_load_xml(path), edition)
        return cls(_load_txt(path), edition)


def _load_xml(path: Path) -> list[Verse]:
    root = ET.parse(path).getroot()
    verses = []
    for sura in root.iter("sura"):
        s = int(sura.get("index"))
        for aya in sura.iter("aya"):
            verses.append(Verse(s, int(aya.get("index")), aya.get("text", "")))
    return verses


def _load_txt(path: Path) -> list[Verse]:
    """Tanzil-Format 'txt-2': sura|aya|text, Kommentare mit '#'."""
    verses = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        s, a, t = line.split("|", 2)
        verses.append(Verse(int(s), int(a), t))
    return verses


def parse_ref(ref: str) -> tuple[int, int]:
    """'2:255' -> (2, 255)"""
    s, a = ref.strip().split(":")
    return int(s), int(a)
