"""Verssuche: erkannten (fehlerbehafteten) Text im gesamten Koran finden.

Ablauf:
1. Der ganze Koran wird als eine durchgehende Wortfolge betrachtet.
2. Kandidatensuche: Jedes Wort der Anfrage (exakt oder ähnlich) "stimmt" für
   die Startposition, an der die Anfrage im Koran beginnen müsste.
   Seltene Wörter zählen mehr (IDF-Gewichtung).
3. Feinabgleich: lokale Alignierung (Smith-Waterman) auf Wortebene um die
   besten Kandidaten. Wortähnlichkeit per Levenshtein (rapidfuzz).
4. Ergebnis: Versbereich + Trefferquote 0..1.

Dieser Prototyp ist die Vorlage für die spätere Swift-Implementierung.
"""

from __future__ import annotations

import math
from collections import defaultdict
from dataclasses import dataclass

import numpy as np
from rapidfuzz import fuzz, process

from quran_corpus import QuranCorpus, normalize

GAP_PENALTY = -0.6
FUZZY_CUTOFF = 75  # Mindestähnlichkeit (0..100) für "ähnliches Wort"
FUZZY_LIMIT = 8
VOTE_SMOOTHING = 3  # Toleranz für eingefügte/fehlende Wörter (± Wörter)
MAX_CANDIDATES = 15
WINDOW_MARGIN = 12


@dataclass
class Match:
    start_verse: int  # globaler Versindex (0..6235)
    end_verse: int
    score: float  # 0..1
    matched_words: int
    start_ref: str
    end_ref: str

    @property
    def ref(self) -> str:
        return self.start_ref if self.start_ref == self.end_ref else f"{self.start_ref}-{self.end_ref}"


class QuranMatcher:
    def __init__(self, corpus: QuranCorpus):
        self.corpus = corpus
        words: list[str] = []
        word_verse: list[int] = []
        for vi, verse in enumerate(corpus.verses):
            for w in normalize(verse.text).split():
                words.append(w)
                word_verse.append(vi)
        self.words = words
        self.word_verse = np.array(word_verse, dtype=np.int32)

        positions: dict[str, list[int]] = defaultdict(list)
        for p, w in enumerate(words):
            positions[w].append(p)
        self.positions = {w: np.array(p, dtype=np.int32) for w, p in positions.items()}
        n = len(words)
        self.idf = {w: math.log(n / len(p)) for w, p in self.positions.items()}
        self.vocab = list(self.positions.keys())
        self._expand_cache: dict[str, list[tuple[str, float]]] = {}

    # -- Kandidatensuche -------------------------------------------------

    def _expand(self, word: str) -> list[tuple[str, float]]:
        """Exaktes Wort plus ähnliche Wörter aus dem Koran-Wortschatz."""
        if word in self._expand_cache:
            return self._expand_cache[word]
        if len(word) <= 2:
            result = [(word, 1.0)] if word in self.positions else []
        else:
            hits = process.extract(
                word, self.vocab, scorer=fuzz.ratio, score_cutoff=FUZZY_CUTOFF, limit=FUZZY_LIMIT
            )
            result = [(h[0], h[1] / 100.0) for h in hits]
        self._expand_cache[word] = result
        return result

    def _candidate_starts(self, query: list[str]) -> list[int]:
        votes = np.zeros(len(self.words) + len(query) + 1, dtype=np.float32)
        for i, w in enumerate(query):
            for v, sim in self._expand(w):
                weight = self.idf[v] * sim * sim
                starts = self.positions[v] - i
                starts = starts[starts >= 0]
                np.add.at(votes, starts, weight)
        if not votes.any():
            return []
        kernel = np.ones(2 * VOTE_SMOOTHING + 1, dtype=np.float32)
        smoothed = np.convolve(votes, kernel, mode="same")

        # beste Startpunkte, Nicht-Maximum-Unterdrückung im Abstand der Anfragelänge
        order = np.argsort(smoothed)[::-1]
        chosen: list[int] = []
        min_dist = max(len(query), 4)
        for p in order[: MAX_CANDIDATES * 50]:
            if smoothed[p] <= 0:
                break
            if all(abs(int(p) - c) >= min_dist for c in chosen):
                chosen.append(int(p))
                if len(chosen) >= MAX_CANDIDATES:
                    break
        return chosen

    # -- Feinabgleich ----------------------------------------------------

    @staticmethod
    def _align(query: list[str], window: list[str]) -> tuple[float, int, int, int]:
        """Smith-Waterman auf Wortebene. Rückgabe: (score, start, ende, gematchte Wörter)."""
        sim = process.cdist(query, window, scorer=fuzz.ratio, dtype=np.float32) / 100.0
        sub = 2.0 * sim - 1.0  # identisch = +1, 50 % ähnlich = 0
        rows, cols = len(query), len(window)
        h = np.zeros((rows + 1, cols + 1), dtype=np.float32)
        best, best_i, best_j = 0.0, 0, 0
        for i in range(1, rows + 1):
            sub_row = sub[i - 1]
            prev = h[i - 1]
            cur = h[i]
            for j in range(1, cols + 1):
                v = max(
                    0.0,
                    prev[j - 1] + sub_row[j - 1],
                    prev[j] + GAP_PENALTY,
                    cur[j - 1] + GAP_PENALTY,
                )
                cur[j] = v
                if v > best:
                    best, best_i, best_j = v, i, j
        # Rückverfolgung für Startposition und Anzahl Treffer
        i, j, matched = best_i, best_j, 0
        while i > 0 and j > 0 and h[i, j] > 0:
            if np.isclose(h[i, j], h[i - 1, j - 1] + sub[i - 1, j - 1]):
                if sim[i - 1, j - 1] >= 0.75:
                    matched += 1
                i, j = i - 1, j - 1
            elif np.isclose(h[i, j], h[i - 1, j] + GAP_PENALTY):
                i -= 1
            else:
                j -= 1
        return float(best), j, best_j - 1, matched

    # -- Öffentliche Schnittstelle --------------------------------------

    def match(self, text: str, top_k: int = 3) -> list[Match]:
        query = normalize(text).split()
        if not query:
            return []
        results: list[Match] = []
        for start in self._candidate_starts(query):
            lo = max(0, start - WINDOW_MARGIN)
            hi = min(len(self.words), start + len(query) + WINDOW_MARGIN)
            score, ws, we, matched = self._align(query, self.words[lo:hi])
            if score <= 0:
                continue
            first, last = lo + ws, lo + we
            sv, ev = int(self.word_verse[first]), int(self.word_verse[last])
            results.append(
                Match(
                    start_verse=sv,
                    end_verse=ev,
                    score=min(1.0, score / len(query)),
                    matched_words=matched,
                    start_ref=self.corpus.verse_at(sv).ref,
                    end_ref=self.corpus.verse_at(ev).ref,
                )
            )
        results.sort(key=lambda m: m.score, reverse=True)
        unique: list[Match] = []
        for m in results:
            if not any(m.start_verse <= u.end_verse and u.start_verse <= m.end_verse for u in unique):
                unique.append(m)
            if len(unique) >= top_k:
                break
        return unique


def ranges_overlap(a_start: int, a_end: int, b_start: int, b_end: int) -> bool:
    return a_start <= b_end and b_start <= a_end
