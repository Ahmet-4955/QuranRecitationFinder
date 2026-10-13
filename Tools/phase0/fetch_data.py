"""Phase 0 – Daten holen.

1. Korantext von Tanzil (simple-clean + uthmani, XML) nach data/
2. Testset aus EveryAyah-Rezitationen bauen (mehrere Rezitatoren):
   - single  : ein ganzer Vers
   - excerpt : Ausschnitt 5–12 s über zwei aufeinanderfolgende Verse
   - noisy   : wie excerpt, plus Rauschen (≈ Handy im Raum)

Aufruf:  python fetch_data.py               (Standard: 8 Clips je Typ und Rezitator)
         python fetch_data.py --per-type 4  (schneller)
         python fetch_data.py --skip-testset
"""

from __future__ import annotations

import argparse
import csv
import io
import random
import sys
import time
from pathlib import Path

import requests

from quran_corpus import QuranCorpus

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data"
TESTSET = DATA / "testset"
SR = 16000

TANZIL_URL = (
    "https://tanzil.net/pub/download/index.php?marks=true&sajdah=true&rub=false"
    "&tatweel=true&quranType={edition}&outType=xml&agree=true"
)
EDITIONS = ["simple-clean", "uthmani"]

EVERYAYAH_URL = "https://everyayah.com/data/{reciter}/{sura:03d}{aya:03d}.mp3"
# Ordnernamen auf everyayah.com; nicht erreichbare werden automatisch übersprungen.
RECITERS = [
    "Alafasy_128kbps",
    "Husary_128kbps",
    "Abdul_Basit_Murattal_192kbps",
    "Minshawy_Murattal_128kbps",
    "Abdurrahmaan_As-Sudais_192kbps",
    "Saood_ash-Shuraym_128kbps",
    "Ghamadi_40kbps",
    "MaherAlMuaiqly128kbps",
    "Yasser_Ad-Dussary_128kbps",
    "Hudhaify_128kbps",
]

session = requests.Session()
session.headers["User-Agent"] = "QuranRecitationFinder-Phase0/1.0"


def get(url: str, retries: int = 3) -> bytes | None:
    for attempt in range(retries):
        try:
            r = session.get(url, timeout=30)
            if r.status_code == 200:
                return r.content
            if r.status_code == 404:
                return None
        except requests.RequestException:
            pass
        time.sleep(2**attempt)
    return None


def fetch_tanzil() -> None:
    DATA.mkdir(exist_ok=True)
    for edition in EDITIONS:
        target = DATA / f"quran-{edition}.xml"
        if target.exists():
            print(f"✓ {target.name} vorhanden")
            continue
        print(f"↓ Tanzil {edition} …")
        content = get(TANZIL_URL.format(edition=edition))
        if not content:
            sys.exit(
                f"✗ Download fehlgeschlagen. Bitte manuell: https://tanzil.net/download/ → "
                f"Quran type '{edition}', Format 'XML' → speichern als {target}"
            )
        target.write_bytes(content)  # unverändert speichern (Tanzil-Lizenz)
        QuranCorpus.load(target)  # prüft 6236 Verse
        print(f"✓ {target.name} ({len(content) // 1024} KB)")


def available_reciters() -> list[str]:
    ok = []
    for r in RECITERS:
        url = EVERYAYAH_URL.format(reciter=r, sura=1, aya=1)
        try:
            resp = session.head(url, timeout=15, allow_redirects=True)
            if resp.status_code == 200:
                ok.append(r)
                continue
        except requests.RequestException:
            pass
        print(f"  – {r} nicht erreichbar, übersprungen")
    return ok


def load_verse_audio(reciter: str, sura: int, aya: int):
    import librosa

    content = get(EVERYAYAH_URL.format(reciter=reciter, sura=sura, aya=aya))
    if not content:
        return None
    audio, _ = librosa.load(io.BytesIO(content), sr=SR, mono=True)
    return audio


def add_noise(audio, rng: random.Random, snr_db: float = 10.0):
    import numpy as np

    noise = np.random.default_rng(rng.randrange(1 << 30)).normal(size=audio.shape).astype("float32")
    signal_power = float((audio**2).mean()) or 1e-8
    noise *= (signal_power / 10 ** (snr_db / 10)) ** 0.5
    return (audio * 0.7 + noise).clip(-1, 1)


def build_testset(per_type: int, seed: int) -> None:
    import numpy as np
    import soundfile as sf

    corpus = QuranCorpus.load(DATA / "quran-simple-clean.xml")
    TESTSET.mkdir(parents=True, exist_ok=True)
    manifest_path = TESTSET / "manifest.csv"
    reciters = available_reciters()
    if len(reciters) < 2:
        sys.exit("✗ Zu wenige Rezitatoren erreichbar – Internetverbindung prüfen.")
    print(f"✓ {len(reciters)} Rezitatoren: {', '.join(reciters)}")

    rng = random.Random(seed)
    rows = []
    n_verses = len(corpus.verses)
    for reciter in reciters:
        for category in ("single", "excerpt", "noisy"):
            made = 0
            while made < per_type:
                vi = rng.randrange(n_verses)
                v = corpus.verse_at(vi)
                clip_id = f"{reciter}_{category}_{made:02d}"
                if category == "single":
                    audio = load_verse_audio(reciter, v.sura, v.aya)
                    if audio is None or len(audio) > 28 * SR or len(audio) < 1.5 * SR:
                        continue
                    start_ref = end_ref = v.ref
                else:
                    nxt = corpus.verse_at(vi + 1) if vi + 1 < n_verses else None
                    if not nxt or nxt.sura != v.sura:
                        continue
                    a1 = load_verse_audio(reciter, v.sura, v.aya)
                    a2 = load_verse_audio(reciter, nxt.sura, nxt.aya)
                    if a1 is None or a2 is None:
                        continue
                    audio = np.concatenate([a1, a2])
                    total = len(audio) / SR
                    length = min(rng.uniform(5, 12), total)
                    t0 = rng.uniform(0, total - length)
                    t1 = t0 + length
                    boundary = len(a1) / SR
                    # Vers zählt als enthalten, wenn mind. 1,5 s davon im Ausschnitt liegen
                    covered = []
                    if min(t1, boundary) - t0 >= 1.5:
                        covered.append(v.ref)
                    if t1 - max(t0, boundary) >= 1.5:
                        covered.append(nxt.ref)
                    if not covered:
                        continue
                    audio = audio[int(t0 * SR) : int(t1 * SR)]
                    if category == "noisy":
                        audio = add_noise(audio, rng)
                    start_ref, end_ref = covered[0], covered[-1]
                path = TESTSET / f"{clip_id}.wav"
                sf.write(path, audio, SR)
                rows.append(
                    {
                        "id": clip_id,
                        "file": str(path.relative_to(ROOT)),
                        "category": category,
                        "speaker": reciter,
                        "start_ref": start_ref,
                        "end_ref": end_ref,
                    }
                )
                made += 1
                print(f"  {clip_id}: {start_ref}–{end_ref} ({len(audio) / SR:.1f} s)")

    with manifest_path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(f"✓ Testset: {len(rows)} Clips → {manifest_path.relative_to(ROOT)}")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--per-type", type=int, default=8, help="Clips je Typ und Rezitator (Standard 8)")
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--skip-testset", action="store_true")
    args = p.parse_args()
    fetch_tanzil()
    if not args.skip_testset:
        build_testset(args.per_type, args.seed)


if __name__ == "__main__":
    main()
