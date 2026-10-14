"""Phase 0 – Auswertung: Transkripte → Verssuche → Trefferquoten.

Liest results/transcripts.json und vergleicht für jedes Modell und jede
Korantext-Ausgabe (simple-clean / uthmani), ob der richtige Vers gefunden wird.

Ausgabe:  results/report.md   (Zusammenfassung + Empfehlung)
          results/details.csv (jeder Clip einzeln)

Aufruf:   python evaluate.py
"""

from __future__ import annotations

import csv
import json
import statistics
from collections import defaultdict
from pathlib import Path

from clip_manifest import load_clips
from quran_corpus import QuranCorpus, parse_ref
from quran_matcher import QuranMatcher, ranges_overlap

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data"
RESULTS = ROOT / "results"
THRESHOLDS = [round(0.30 + 0.05 * i, 2) for i in range(12)]  # 0.30 … 0.85
TIE_MARGIN = 0.01
# Abnahmekriterium aus dem Plan
TARGET_PRECISION = 0.95
TARGET_RECALL_OWN = 0.85


def evaluate_clip(matcher: QuranMatcher, clip: dict, text: str) -> dict:
    corpus = matcher.corpus
    ts = corpus.verse_index(*parse_ref(clip["start_ref"]))
    te = corpus.verse_index(*parse_ref(clip["end_ref"]))
    results = matcher.match(text, top_k=5)
    if not results:
        return {"score": 0.0, "pred": "", "top1": False, "top3": False}
    best = results[0]
    tied = [r for r in results if r.score >= best.score - TIE_MARGIN]
    top1 = any(ranges_overlap(r.start_verse, r.end_verse, ts, te) for r in tied)
    top3 = top1 or any(ranges_overlap(r.start_verse, r.end_verse, ts, te) for r in results[:3])
    return {"score": round(best.score, 3), "pred": best.ref, "top1": top1, "top3": top3}


def threshold_table(rows: list[dict]) -> list[dict]:
    out = []
    n = len(rows)
    for t in THRESHOLDS:
        accepted = [r for r in rows if r["score"] >= t]
        correct = sum(r["top1"] for r in accepted)
        out.append(
            {
                "threshold": t,
                "accepted": len(accepted) / n if n else 0,
                "precision": correct / len(accepted) if accepted else 1.0,
                "recall": correct / n if n else 0,
            }
        )
    return out


def best_threshold(table: list[dict]) -> dict:
    """Niedrigste Schwelle, die die Ziel-Präzision erreicht (max. Trefferquote bei wenig Fehlalarmen)."""
    ok = [r for r in table if r["precision"] >= TARGET_PRECISION]
    # höchste Trefferquote; bei Gleichstand höhere Präzision; dann niedrigste Schwelle
    return (max(ok, key=lambda r: (r["recall"], r["precision"], -r["threshold"])) if ok
            else max(table, key=lambda r: r["precision"]))


def pct(x: float) -> str:
    return f"{x * 100:.0f} %"


def main() -> None:
    cache_path = RESULTS / "transcripts.json"
    if not cache_path.exists():
        raise SystemExit("results/transcripts.json fehlt – erst transcribe.py ausführen.")
    transcripts = json.loads(cache_path.read_text(encoding="utf-8"))
    clips = {c["id"]: c for c in load_clips()}

    matchers = {}
    for edition in ("simple-clean", "uthmani"):
        path = DATA / f"quran-{edition}.xml"
        if path.exists():
            matchers[edition] = QuranMatcher(QuranCorpus.load(path, edition))
    if not matchers:
        raise SystemExit("Korantext fehlt – erst fetch_data.py ausführen.")

    detail_rows = []
    summary = []
    for model_id, per_clip in transcripts.items():
        latencies = [v["seconds"] for v in per_clip.values()]
        rtf = [v["seconds"] / v["audio_seconds"] for v in per_clip.values() if v.get("audio_seconds")]
        for edition, matcher in matchers.items():
            rows = []
            for clip_id, t in per_clip.items():
                clip = clips.get(clip_id)
                if not clip:
                    continue
                r = evaluate_clip(matcher, clip, t["text"])
                r.update(
                    model=model_id,
                    edition=edition,
                    id=clip_id,
                    category=clip["category"],
                    speaker=clip.get("speaker", ""),
                    truth=clip["start_ref"] if clip["start_ref"] == clip["end_ref"] else f"{clip['start_ref']}-{clip['end_ref']}",
                    transcript=t["text"],
                )
                rows.append(r)
            if not rows:
                continue
            detail_rows.extend(rows)
            by_cat = defaultdict(list)
            for r in rows:
                by_cat[r["category"]].append(r)
            table = threshold_table(rows)
            summary.append(
                {
                    "model": model_id,
                    "edition": edition,
                    "n": len(rows),
                    "top1": sum(r["top1"] for r in rows) / len(rows),
                    "top3": sum(r["top3"] for r in rows) / len(rows),
                    "by_cat": {c: (sum(r["top1"] for r in rs) / len(rs), len(rs)) for c, rs in sorted(by_cat.items())},
                    "own_table": threshold_table(by_cat["own"]) if by_cat.get("own") else None,
                    "table": table,
                    "best": best_threshold(table),
                    "latency": statistics.median(latencies) if latencies else 0,
                    "rtf": statistics.median(rtf) if rtf else 0,
                }
            )

    RESULTS.mkdir(exist_ok=True)
    with (RESULTS / "details.csv").open("w", newline="", encoding="utf-8") as f:
        fields = ["model", "edition", "id", "category", "speaker", "truth", "pred", "score", "top1", "top3", "transcript"]
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(detail_rows)

    report = render_report(summary)
    (RESULTS / "report.md").write_text(report, encoding="utf-8")
    print(report)


def render_report(summary: list[dict]) -> str:
    from datetime import datetime

    lines = [
        "# Phase 0 – Ergebnis Machbarkeitstest",
        "",
        f"Erstellt: {datetime.now():%d.%m.%Y %H:%M}",
        "",
        "## Übersicht",
        "",
        "| Modell | Korantext | Clips | Top-1 | Top-3 | Schwelle | Präzision | Trefferquote | Median Zeit/Clip (Mac) |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for s in summary:
        b = s["best"]
        lines.append(
            f"| `{s['model']}` | {s['edition']} | {s['n']} | {pct(s['top1'])} | {pct(s['top3'])} | "
            f"{b['threshold']:.2f} | {pct(b['precision'])} | {pct(b['recall'])} | {s['latency']:.2f} s |"
        )
    lines += ["", "## Nach Clip-Typ (Top-1)", ""]
    cats = sorted({c for s in summary for c in s["by_cat"]})
    lines.append("| Modell | Korantext | " + " | ".join(cats) + " |")
    lines.append("|---|---|" + "---|" * len(cats))
    for s in summary:
        cells = [f"{pct(s['by_cat'][c][0])} (n={s['by_cat'][c][1]})" if c in s["by_cat"] else "–" for c in cats]
        lines.append(f"| `{s['model']}` | {s['edition']} | " + " | ".join(cells) + " |")

    lines += [
        "",
        "## Begriffe",
        "",
        "- **Top-1**: bester Treffer enthält den richtigen Vers (gleichlautende Verse zählen gemeinsam).",
        "- **Top-3**: richtiger Vers unter den ersten drei Vorschlägen.",
        f"- **Schwelle**: niedrigste Trefferquote-Schwelle, bei der ≥ {pct(TARGET_PRECISION)} der angezeigten Treffer stimmen.",
        "- **Präzision**: Anteil richtiger unter den angezeigten Treffern (Rest = Fehlalarm).",
        "- **Trefferquote**: Anteil aller Clips, die richtig erkannt *und* angezeigt werden.",
        "",
        "## Bewertung",
        "",
    ]
    own = [s for s in summary if s["own_table"]]
    if not own:
        lines += [
            "⚠ **Noch keine eigenen Aufnahmen ausgewertet.** Die EveryAyah-Clips sind Studioaufnahmen und",
            "vermutlich Teil der Trainingsdaten der Tarteel-Modelle – die Zahlen oben sind daher zu optimistisch.",
            "Eigene Aufnahmen in `clips/own/` ablegen (siehe README) und `transcribe.py` + `evaluate.py` erneut starten.",
        ]
    else:
        for s in own:
            ob = best_threshold(s["own_table"])
            verdict = "✅ erfüllt" if ob["precision"] >= TARGET_PRECISION and ob["recall"] >= TARGET_RECALL_OWN else "❌ nicht erfüllt"
            lines.append(
                f"- `{s['model']}` / {s['edition']}: eigene Aufnahmen – Präzision {pct(ob['precision'])}, "
                f"Trefferquote {pct(ob['recall'])} bei Schwelle {ob['threshold']:.2f} → {verdict} "
                f"(Ziel: Präzision ≥ {pct(TARGET_PRECISION)}, Trefferquote ≥ {pct(TARGET_RECALL_OWN)})"
            )
    lines += ["", "Einzelergebnisse: `results/details.csv`", ""]
    return "\n".join(lines)


if __name__ == "__main__":
    main()
