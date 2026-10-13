"""Vergleichsfälle für die Swift-Verssuche erzeugen.

Führt den Python-Prototyp auf dem Korantext aus, der in der App steckt
(QuranRecitationFinder/Resources/Quran/quran-simple-clean.xml), und schreibt
Anfragen + erwartete Ergebnisse nach QuranRecitationFinderTests/MatcherFixtures.swift.
Der Swift-Test `matchesPythonPrototype` prüft dann, dass beide gleich rechnen.

Aufruf (nach Tools/data/build_resources.py):   python export_swift_fixtures.py
"""

from __future__ import annotations

import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "tests"))

from quran_corpus import QuranCorpus  # noqa: E402
from quran_matcher import QuranMatcher  # noqa: E402
from test_matcher import _corrupt  # noqa: E402

CORPUS = REPO / "QuranRecitationFinder" / "Resources" / "Quran" / "quran-simple-clean.xml"
OUTPUT = REPO / "QuranRecitationFinderTests" / "MatcherFixtures.swift"
TIE_MARGIN = 0.01


def swift_string(text: str) -> str:
    bs = chr(92)
    out = "".join(bs + "u{%04X}" % ord(c) if ord(c) > 127 else (bs + '"' if c == '"' else c) for c in text)
    return f'"{out}"'


def main() -> None:
    if not CORPUS.exists():
        sys.exit(f"✗ {CORPUS.relative_to(REPO)} fehlt – erst Tools/data/build_resources.py ausführen.")
    corpus = QuranCorpus.load(CORPUS, "simple-clean")
    matcher = QuranMatcher(corpus)
    rng = random.Random(2026)

    queries = [
        "الله لا اله الا هو الحي القيوم",
        "فباي الاء ربكما تكذبان",
        "بسم الله الرحمن الرحيم",
        "اهدنا الصراط المستقيم صراط الذين انعمت عليهم",
        "هذا نص عربي حديث عن الهاتف والسيارة",
    ]
    for _ in range(60):
        length = rng.choice([3, 6, 12, 20])
        start = rng.randrange(len(matcher.words) - length)
        noisy = _corrupt(matcher.words[start : start + length], rng, rng.choice([0.0, 0.15, 0.3]), matcher.vocab)
        queries.append(" ".join(noisy))

    lines = [
        "// Automatisch erzeugt von Tools/phase0/export_swift_fixtures.py – nicht von Hand ändern.",
        "// Erwartete Ergebnisse des Python-Prototyps auf dem gebündelten quran-simple-clean.xml.",
        "",
        "enum MatcherFixtures {",
        "    struct Case {",
        "        let query: String",
        "        /// Startverse aller gleichwertigen besten Treffer (Score >= bester - 0,01)",
        "        let acceptableStarts: [String]",
        "        let bestScore: Float",
        "    }",
        "",
        "    static let cases: [Case] = [",
    ]
    count = 0
    for q in queries:
        results = matcher.match(q, top_k=5)
        if not results:
            continue
        count += 1
        best = results[0].score
        starts = sorted({r.start_ref for r in results if r.score >= best - TIE_MARGIN})
        refs = ", ".join(f'"{s}"' for s in starts)
        lines.append(f"        Case(query: {swift_string(q)}, acceptableStarts: [{refs}], bestScore: {best:.4f}),")
    lines += ["    ]", "}", ""]
    OUTPUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"✓ {count} Fälle → {OUTPUT.relative_to(REPO)}")


if __name__ == "__main__":
    main()
