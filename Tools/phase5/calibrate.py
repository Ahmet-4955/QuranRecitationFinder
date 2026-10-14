"""Phase 5 – Schwelle der Verssuche aus echten Messungen bestimmen.

Quellen (eine oder beide):
  --phase0 Tools/phase0/results/details.csv   Ergebnisse des Machbarkeitstests (Mac)
  --app    testprotokoll-*.json               Export aus der App (Einstellungen → Testprotokoll)

Ergebnis:
  - Tabelle Präzision / Trefferquote je Schwelle
  - Empfehlung: niedrigste Schwelle mit Präzision ≥ Ziel (Standard 95 %)
  - schreibt QuranRecitationFinder/Resources/recognition-config.json (außer mit --dry-run)

Aufruf:   python calibrate.py --phase0 ../phase0/results/details.csv --model tarteel-ai/whisper-base-ar-quran
          python calibrate.py --app ~/Downloads/testprotokoll-2026-10-20.json
          python calibrate.py --phase0 … --app … --dry-run
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CONFIG = REPO / "QuranRecitationFinder" / "Resources" / "recognition-config.json"
THRESHOLDS = [round(0.30 + 0.025 * i, 3) for i in range(27)]  # 0.30 … 0.95
MIN_SAMPLES = 20
EDITION_NAMES = {"simple-clean": "simpleClean", "uthmani": "uthmani"}


@dataclass
class Sample:
    score: float
    correct: bool
    source: str  # "phase0:<kategorie>" oder "app"
    words: int | None = None


def load_phase0(path: Path, model: str | None) -> dict[str, list[Sample]]:
    """Je Korantext-Ausgabe eine Liste von Messpunkten."""
    by_edition: dict[str, list[Sample]] = defaultdict(list)
    models = set()
    with path.open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            models.add(row["model"])
            if model and row["model"] != model:
                continue
            by_edition[row["edition"]].append(
                Sample(float(row["score"]), row["top1"] == "True", f"phase0:{row['category']}",
                       len(row.get("transcript", "").split()) or None)
            )
    if not by_edition:
        sys.exit(f"✗ Keine Zeilen für Modell {model!r}. Vorhanden: {', '.join(sorted(models))}")
    return by_edition


def load_app(path: Path) -> list[Sample]:
    records = json.loads(path.read_text(encoding="utf-8"))
    samples = []
    for r in records:
        if r.get("verdict") not in ("correct", "wrong") or not r.get("candidates"):
            continue  # unbewertet oder ohne Kandidat
        samples.append(Sample(float(r["candidates"][0]["score"]), r["verdict"] == "correct", "app", r.get("wordCount")))
    return samples


def table(samples: list[Sample]) -> list[dict]:
    n = len(samples)
    rows = []
    for t in THRESHOLDS:
        accepted = [s for s in samples if s.score >= t]
        correct = sum(s.correct for s in accepted)
        rows.append({
            "threshold": t,
            "precision": correct / len(accepted) if accepted else 1.0,
            "recall": correct / n if n else 0.0,
            "accepted": len(accepted),
        })
    return rows


def recommend(rows: list[dict], target: float) -> dict | None:
    ok = [r for r in rows if r["precision"] >= target and r["accepted"] > 0]
    # höchste Trefferquote; bei Gleichstand höhere Präzision; dann niedrigste Schwelle
    return max(ok, key=lambda r: (r["recall"], r["precision"], -r["threshold"])) if ok else None


def print_table(title: str, rows: list[dict], best: dict | None) -> None:
    print(f"\n{title}")
    print("  Schwelle  Präzision  Trefferquote  angezeigt")
    for r in rows:
        mark = "  ← Empfehlung" if best and r["threshold"] == best["threshold"] else ""
        print(f"  {r['threshold']:.3f}     {r['precision'] * 100:5.1f} %    {r['recall'] * 100:5.1f} %     {r['accepted']:4d}{mark}")


def word_count_report(samples: list[Sample]) -> None:
    buckets = defaultdict(list)
    for s in samples:
        if s.words is None:
            continue
        key = "1–2" if s.words <= 2 else "3–4" if s.words <= 4 else "5–9" if s.words <= 9 else "10+"
        buckets[key].append(s.correct)
    if buckets:
        print("\nTrefferquote nach Wortanzahl (bester Treffer richtig):")
        for key in ("1–2", "3–4", "5–9", "10+"):
            if key in buckets:
                v = buckets[key]
                print(f"  {key:4} Wörter: {sum(v) / len(v) * 100:5.1f} %  (n={len(v)})")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--phase0", type=Path, help="Tools/phase0/results/details.csv")
    p.add_argument("--model", help="Modell aus Phase 0, z. B. tarteel-ai/whisper-base-ar-quran")
    p.add_argument("--app", type=Path, action="append", default=[], help="App-Export (mehrfach möglich)")
    p.add_argument("--target-precision", type=float, default=0.95)
    p.add_argument("--dry-run", action="store_true", help="nur anzeigen, Konfiguration nicht schreiben")
    args = p.parse_args()
    if not args.phase0 and not args.app:
        p.error("mindestens --phase0 oder --app angeben")

    edition = None
    samples: list[Sample] = []
    sources = []
    if args.phase0:
        by_edition = load_phase0(args.phase0, args.model)
        # Ausgabe wählen, die bei Ziel-Präzision die höchste Trefferquote hat (eigene Aufnahmen bevorzugt)
        scored = []
        for ed, s in by_edition.items():
            own = [x for x in s if x.source == "phase0:own"]
            basis = own if len(own) >= MIN_SAMPLES else s
            best = recommend(table(basis), args.target_precision)
            scored.append(((best or {"recall": 0})["recall"], ed, s))
            print_table(f"Phase 0 – Korantext {ed} ({'eigene Aufnahmen' if basis is own else 'alle Clips'}, n={len(basis)})",
                        table(basis), best)
        _, edition, chosen = max(scored, key=lambda x: x[0])
        own = [x for x in chosen if x.source == "phase0:own"]
        samples += own if len(own) >= MIN_SAMPLES else chosen
        sources.append(f"Phase 0 ({args.model or 'alle Modelle'}, {edition}, n={len(samples)})")
    for path in args.app:
        app_samples = load_app(path)
        samples += app_samples
        sources.append(f"App-Protokoll {path.name} (n={len(app_samples)})")

    if not samples:
        sys.exit("✗ Keine bewerteten Messpunkte gefunden.")
    rows = table(samples)
    best = recommend(rows, args.target_precision)
    print_table(f"Gesamt (n={len(samples)})", rows, best)
    word_count_report(samples)

    if len(samples) < MIN_SAMPLES:
        print(f"\n⚠ Nur {len(samples)} Messpunkte – Empfehlung unsicher, Ziel ≥ {MIN_SAMPLES}.")
    if not best:
        sys.exit(f"\n✗ Keine Schwelle erreicht {args.target_precision:.0%} Präzision – Erkennung zuerst verbessern "
                 "(größeres Modell, längere Aufnahmen). Konfiguration unverändert.")

    print(f"\n→ Empfehlung: Schwelle {best['threshold']:.3f} "
          f"(Präzision {best['precision']:.1%}, Trefferquote {best['recall']:.1%})")
    config = json.loads(CONFIG.read_text(encoding="utf-8")) if CONFIG.exists() else {}
    config["acceptThreshold"] = best["threshold"]
    if edition:
        config["edition"] = EDITION_NAMES.get(edition, edition)
    config["calibratedAt"] = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    config["calibrationNote"] = (f"Ziel-Präzision {args.target_precision:.0%}; Präzision {best['precision']:.1%}, "
                                 f"Trefferquote {best['recall']:.1%}; Quellen: " + "; ".join(sources))
    if args.dry_run:
        print("(--dry-run: nicht geschrieben)\n" + json.dumps(config, indent=2, ensure_ascii=False))
        return
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    CONFIG.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"✓ {CONFIG.relative_to(REPO)} aktualisiert – App neu bauen, dann committen.")


if __name__ == "__main__":
    main()
