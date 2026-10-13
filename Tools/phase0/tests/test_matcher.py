"""Tests der Verssuche mit künstlich verfälschten Koranausschnitten.

Benötigt den Korantext: data/quran-simple-clean.xml bzw. data/quran-uthmani.xml
(per fetch_data.py) oder Pfad in Umgebungsvariable QURAN_CORPUS.
"""

import os
import random
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from quran_corpus import QuranCorpus, normalize  # noqa: E402
from quran_matcher import QuranMatcher, ranges_overlap  # noqa: E402


def _corpus_path() -> Path | None:
    candidates = [os.environ.get("QURAN_CORPUS")] + [
        str(ROOT / "data" / n) for n in ("quran-simple-clean.xml", "quran-uthmani.xml")
    ]
    for c in candidates:
        if c and Path(c).exists():
            return Path(c)
    return None


CORPUS_PATH = _corpus_path()
pytestmark = pytest.mark.skipif(CORPUS_PATH is None, reason="Korantext fehlt – erst fetch_data.py ausführen")


@pytest.fixture(scope="module")
def matcher():
    return QuranMatcher(QuranCorpus.load(CORPUS_PATH))


def test_corpus_complete(matcher):
    assert len(matcher.corpus.verses) == 6236
    assert len(matcher.words) > 75000


def test_normalize_removes_diacritics():
    assert normalize("ٱلرَّحْمَٰنِ ٱلرَّحِيمِ") == "الرحمن الرحيم"
    assert normalize("ٱلَّذِى") == "الذي"


@pytest.mark.parametrize(
    "text, expected",
    [
        ("الله لا اله الا هو الحي القيوم لا تاخذه سنه ولا نوم", "2:255"),
        ("قل هو الله احد الله الصمد", "112:1"),
        ("والعصر ان الانسان لفي خسر", "103:1"),
        ("قل اعوذ برب الفلق من شر ما خلق", "113:1"),
    ],
)
def test_known_passages(matcher, text, expected):
    best = matcher.match(text)[0]
    assert best.start_ref == expected
    assert best.score > 0.8


def test_repeated_verse_reports_tie(matcher):
    results = matcher.match("فباي الاء ربكما تكذبان")
    assert all(r.start_ref.startswith("55:") for r in results)
    assert results[0].score - results[-1].score < 0.01


def test_garbage_scores_low(matcher):
    results = matcher.match("هذا نص عربي حديث عن الهاتف والسيارة والحاسوب")
    assert not results or results[0].score < 0.5


def test_empty_input(matcher):
    assert matcher.match("") == []
    assert matcher.match("hello world 123") == []


def _corrupt(words: list[str], rng: random.Random, rate: float, vocab: list[str]) -> list[str]:
    """Typische Erkennungsfehler: Buchstabe vertauscht, Wort fehlt, Wort eingefügt."""
    letters = "ابتثجحخدذرزسشصضطظعغفقكلمنهوي"
    out = []
    for w in words:
        r = rng.random()
        if r < rate / 3:
            continue  # Wort ausgelassen
        if r < 2 * rate / 3 and len(w) > 2:
            i = rng.randrange(len(w))
            w = w[:i] + rng.choice(letters) + w[i + 1 :]  # Buchstabe falsch
        out.append(w)
        if rng.random() < rate / 3:
            out.append(rng.choice(vocab))  # fremdes Wort eingefügt
    return out


@pytest.mark.parametrize("length, rate, min_accuracy", [(6, 0.15, 0.85), (12, 0.2, 0.95), (20, 0.3, 0.95)])
def test_random_excerpts_with_errors(matcher, length, rate, min_accuracy):
    rng = random.Random(42 + length)
    trials, hits = 200, 0
    for _ in range(trials):
        start = rng.randrange(len(matcher.words) - length)
        words = matcher.words[start : start + length]
        true_sv = int(matcher.word_verse[start])
        true_ev = int(matcher.word_verse[start + length - 1])
        noisy = _corrupt(words, rng, rate, matcher.vocab)
        results = matcher.match(" ".join(noisy))
        if not results:
            continue
        best = results[0].score
        tied = [r for r in results if r.score >= best - 0.01]
        if any(ranges_overlap(r.start_verse, r.end_verse, true_sv, true_ev) for r in tied):
            hits += 1
    accuracy = hits / trials
    print(f"Länge {length}, Fehlerrate {rate}: {accuracy:.1%}")
    assert accuracy >= min_accuracy
