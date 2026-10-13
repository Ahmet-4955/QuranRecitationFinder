"""Offline-Test von build_resources.py mit simulierten Tanzil-/QuranEnc-Antworten."""

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_resources as br  # noqa: E402

# Versanzahl je Sure (Standard-Zählung, Summe 6236)
AYAS = [
    7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99, 128, 111, 110, 98, 135,
    112, 78, 118, 64, 77, 227, 93, 88, 69, 60, 34, 30, 73, 54, 45, 83, 182, 88, 75, 85, 54, 53,
    89, 59, 37, 35, 38, 29, 18, 45, 60, 49, 62, 55, 78, 96, 29, 22, 24, 13, 14, 11, 11, 18, 12,
    12, 30, 52, 52, 44, 28, 28, 20, 56, 40, 31, 50, 40, 46, 42, 29, 19, 36, 25, 22, 17, 19, 26,
    30, 20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11, 11, 8, 3, 9, 5, 4, 7, 3, 6, 3, 5, 4, 5, 6,
]


def _quran_xml() -> bytes:
    suras = "".join(
        f'<sura index="{s}" name="S{s}">' + "".join(f'<aya index="{a}" text="t{s}_{a}"/>' for a in range(1, n + 1)) + "</sura>"
        for s, n in enumerate(AYAS, 1)
    )
    return f"<quran>{suras}</quran>".encode()


def _meta_xml() -> bytes:
    suras = "".join(f'<sura index="{s}" ayas="{n}" name="S{s}" tname="T{s}" ename="E{s}" type="Meccan"/>' for s, n in enumerate(AYAS, 1))
    return f'<quran type="metadata"><suras alias="chapters">{suras}</suras></quran>'.encode()


LISTS = {
    "de": [{"key": "german_bubenheim", "language_iso_code": "de", "version": "1.0.1", "title": "Bubenheim & Elyas"}],
    "tr": [{"key": "turkish_shaban", "language_iso_code": "tr", "version": "1.1", "title": "Shaban"}],
    "en": [{"key": "english_saheeh", "language_iso_code": "en", "version": "1.0.4", "title": "Saheeh International"}],
}


def fake_get(url: str, retries: int = 4) -> bytes:
    if "quranType=" in url:
        return _quran_xml()
    if url.endswith("quran-data.xml"):
        return _meta_xml()
    if "/translations/list/" in url:
        return json.dumps({"translations": LISTS[url.rsplit("/", 1)[1]]}).encode()
    if "/translation/sura/" in url:
        key, sura = url.rsplit("/", 2)[1:]
        rows = [
            {"id": str(a), "sura": sura, "aya": str(a), "arabic_text": "x", "translation": f"{key} {sura}:{a}", "footnotes": ""}
            for a in range(1, AYAS[int(sura) - 1] + 1)
        ]
        return json.dumps({"result": rows}).encode()
    raise AssertionError(url)


@pytest.fixture
def env(tmp_path, monkeypatch):
    monkeypatch.setattr(br, "get", fake_get)
    monkeypatch.setattr(br.time, "sleep", lambda s: None)
    monkeypatch.setattr(br, "ROOT", tmp_path)
    monkeypatch.setattr(br, "RESOURCES", tmp_path / "Resources")
    monkeypatch.setattr(br, "QURAN_DIR", tmp_path / "Resources" / "Quran")
    monkeypatch.setattr(br, "TRANSLATION_DIR", tmp_path / "Resources" / "Translations")
    return tmp_path / "Resources"


def test_sum_of_ayas():
    assert sum(AYAS) == 6236 and len(AYAS) == 114


def test_full_build(env, monkeypatch):
    monkeypatch.setattr(sys, "argv", ["build_resources.py"])
    br.main()
    assert {p.name for p in (env / "Quran").iterdir()} == {"quran-uthmani.xml", "quran-simple-clean.xml", "quran-data.xml"}
    index = json.loads((env / "Translations" / "translations-index.json").read_text())
    keys = [t["key"] for t in index["translations"]]
    assert keys == ["german_bubenheim", "turkish_shaban", "english_saheeh"]  # Fallback bei tr greift
    de = json.loads((env / "Translations" / "translation-german_bubenheim.json").read_text())
    assert len(de["verses"]) == 6236
    assert de["verses"][0] == {"sura": 1, "aya": 1, "text": "german_bubenheim 1:1", "footnotes": None}
    assert de["version"] == "1.0.1"
    assert "QuranEnc" in (env / "SOURCES.md").read_text()


def test_unknown_override_lists_options(env, monkeypatch):
    monkeypatch.setattr(sys, "argv", ["build_resources.py", "--tr", "turkish_gibts_nicht"])
    with pytest.raises(SystemExit) as e:
        br.main()
    assert "turkish_shaban" in str(e.value)


def test_incomplete_translation_is_rejected(env, monkeypatch):
    def broken(url, retries=4):
        data = fake_get(url)
        if url.endswith("/translation/sura/english_saheeh/2"):
            rows = json.loads(data)["result"][:-1]  # letzter Vers fehlt
            return json.dumps({"result": rows}).encode()
        return data

    monkeypatch.setattr(br, "get", broken)
    monkeypatch.setattr(sys, "argv", ["build_resources.py"])
    with pytest.raises(SystemExit) as e:
        br.main()
    assert "Sure 2" in str(e.value)
