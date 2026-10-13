"""Gemeinsames Einlesen der Clip-Listen (EveryAyah-Testset + eigene Aufnahmen)."""

from __future__ import annotations

import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MANIFESTS = [ROOT / "data" / "testset" / "manifest.csv", ROOT / "clips" / "own" / "manifest.csv"]


def load_clips() -> list[dict]:
    clips = []
    for manifest in MANIFESTS:
        if not manifest.exists():
            continue
        with manifest.open(encoding="utf-8") as f:
            for row in csv.DictReader(f):
                if not row.get("file") or row["file"].startswith("#"):
                    continue
                row = {k: (v or "").strip() for k, v in row.items()}
                path = Path(row["file"])
                if not path.is_absolute():
                    # eigene Aufnahmen: Pfad relativ zu clips/own/, Testset: relativ zu ROOT
                    base = manifest.parent if manifest.parent.name == "own" else ROOT
                    path = base / path
                row["path"] = str(path)
                row.setdefault("category", "own")
                row["category"] = row["category"] or "own"
                row.setdefault("id", path.stem)
                row["id"] = row["id"] or f"own_{path.stem}"
                row["end_ref"] = row.get("end_ref") or row["start_ref"]
                if not path.exists():
                    print(f"⚠ Datei fehlt, übersprungen: {path}")
                    continue
                clips.append(row)
    return clips
