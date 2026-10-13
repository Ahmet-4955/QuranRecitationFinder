"""Ersatz-Ressourcen für die Kompilierprüfung, solange die echten Daten nicht im Repo liegen.

- Korantext: Tanzil Uthmani 1.0.2 aus dem PyPI-Paket `pyquran` (unverändert, CC BY 3.0),
  für beide Ausgaben verwendet
- Metadaten: aus der Standard-Versanzahl erzeugt (Surennamen nur Platzhalter)
- Übersetzungen: Platzhaltertexte im echten Dateiformat

Erzeugt wird über das echte Tools/data/build_resources.py (nur die Downloads sind umgeleitet),
damit Format und Prüfungen identisch sind.

Aufruf:  python make_standin.py <Zielordner>
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(REPO / "Tools" / "data"))
sys.path.insert(0, str(REPO / "Tools" / "data" / "tests"))

import build_resources as br  # noqa: E402
import test_build_resources as fake  # noqa: E402

MEDINAN = {2, 3, 4, 5, 8, 9, 22, 24, 33, 47, 48, 49, 55, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 76, 98, 99, 110}


def pyquran_text() -> bytes:
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run([sys.executable, "-m", "pip", "download", "pyquran==1.0.1", "--no-deps", "-q", "-d", tmp],
                       check=True)
        wheel = next(Path(tmp).glob("pyquran-*.whl"))
        with zipfile.ZipFile(wheel) as z:
            return z.read("pyquran/QuranCorpus/quran-uthmani.xml")


def metadata() -> bytes:
    suras = "".join(
        f'<sura index="{i}" ayas="{n}" name="S{i}" tname="Sura-{i}" ename="Surah {i}" '
        f'type="{"Medinan" if i in MEDINAN else "Meccan"}"/>'
        for i, n in enumerate(fake.AYAS, 1)
    )
    return f'<quran type="metadata"><suras alias="chapters">{suras}</suras></quran>'.encode()


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    target = Path(sys.argv[1]).resolve()
    text = pyquran_text()
    meta = metadata()

    def get(url: str, retries: int = 4) -> bytes:
        if "quranType=" in url:
            return text
        if url.endswith("quran-data.xml"):
            return meta
        return fake.fake_get(url)  # QuranEnc-Listen und -Übersetzungen (Platzhalter)

    br.get = get
    br.time.sleep = lambda s: None
    br.RESOURCES, br.QURAN_DIR, br.TRANSLATION_DIR = target, target / "Quran", target / "Translations"
    br.ROOT = target.parent
    sys.argv = ["build_resources.py"]
    br.main()


if __name__ == "__main__":
    main()
