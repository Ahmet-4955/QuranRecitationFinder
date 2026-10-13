# Phase 0 – Machbarkeitstest Spracherkennung

Stand: 13.10.2026

**Frage:** Erkennt das Tarteel-Whisper-Modell zusammen mit der Verssuche
Koranausschnitte zuverlässig genug – auch bei eigenen Handyaufnahmen?

**Getestet werden:**

| Modell | Lizenz | Größe (Download) |
|---|---|---|
| `tarteel-ai/whisper-tiny-ar-quran` | Apache 2.0 | ca. 150 MB |
| `tarteel-ai/whisper-base-ar-quran` | Apache 2.0 | ca. 290 MB |

Beide sind auch kommerziell nutzbar. Weitere Modelle per `--models` möglich,
z. B. `openai/whisper-base` als Vergleich ohne Koran-Training.

---

## Schritt 1 – Einrichtung (einmalig, ca. 10 Min.)

Terminal öffnen, im Repo-Ordner:

```bash
brew install python@3.11 ffmpeg          # ffmpeg wird für .m4a-Aufnahmen gebraucht
cd Tools/phase0
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

> Python 3.11/3.12 verwenden – die spätere Core-ML-Konvertierung (Phase 3)
> läuft nicht mit 3.13.

## Schritt 2 – Daten holen (ca. 5–15 Min.)

```bash
python fetch_data.py
```

- lädt den Korantext von Tanzil (`data/quran-simple-clean.xml`, `data/quran-uthmani.xml`)
- baut ein Testset aus EveryAyah-Rezitationen (bis zu 10 Rezitatoren × 3 Typen × 8 Clips):
  - `single` – ganzer Vers
  - `excerpt` – Ausschnitt 5–12 s, auch über Versgrenzen
  - `noisy` – Ausschnitt mit Rauschen

Schneller Probelauf: `python fetch_data.py --per-type 2`

Kontrolle der Verssuche (sollte „12 passed“ melden):

```bash
python -m pytest -q tests
```

## Schritt 3 – Eigene Aufnahmen (wichtigster Teil!)

Die EveryAyah-Clips sind Studioaufnahmen und vermutlich Teil der
Trainingsdaten → Ergebnisse dort sind zu optimistisch. **Aussagekräftig sind
nur eigene Aufnahmen.**

Ziel: **20–30 Aufnahmen, je 5–15 s**, mit dem iPhone (App „Sprachmemos“).
Bunt gemischt:

| Situation | Anzahl |
|---|---|
| Rezitation aus Lautsprecher/TV/Handy abgespielt und aufgenommen (verschiedene Rezitatoren) | 8–10 |
| Selbst rezitiert | 5–8 |
| Mit Hintergrundgeräusch (Auto, Küche, Gespräch) | 4–6 |
| Mitten im Vers begonnen / über Versgrenze | 4–6 |
| Sehr kurz (2–4 Wörter) | 2–3 |

Ablauf:

1. Aufnahmen per AirDrop auf den Mac → in `Tools/phase0/clips/own/` legen
   (Format egal: .m4a, .mp3, .wav).
2. Für jede Datei eine Zeile in `clips/own/manifest.csv` ergänzen:

   ```csv
   file,start_ref,end_ref,speaker,notes
   fatiha_ich.m4a,1:1,1:7,ahmet,selbst rezitiert Wohnzimmer
   kursi_tv.m4a,2:255,2:255,TV-Sudais,Fernseher 3 m Abstand
   mulk_auto.m4a,67:1,67:2,Radio,Auto 100 km/h
   ```

   `start_ref`/`end_ref` = erster/letzter Vers, der im Ausschnitt **hörbar** ist.

Die Aufnahmen bleiben lokal (per `.gitignore` vom Repo ausgeschlossen).

## Schritt 4 – Transkribieren (ca. 5–20 Min.)

```bash
python transcribe.py
```

Läuft auf der Apple-GPU (MPS). Ergebnisse werden zwischengespeichert –
nach neuen Aufnahmen einfach erneut starten, nur Neues wird bearbeitet.

## Schritt 5 – Auswerten

```bash
python evaluate.py
```

Erzeugt `results/report.md` (Zusammenfassung) und `results/details.csv`
(jeder Clip mit erkanntem Text, Treffer, Score).

## Entscheidung nach Phase 0

| Ergebnis eigene Aufnahmen | Entscheidung |
|---|---|
| Präzision ≥ 95 % **und** Trefferquote ≥ 85 % | ✅ Weiter mit Phase 1–4, kleinstes Modell nehmen, das das erfüllt |
| Präzision ok, Trefferquote 60–85 % | ⚠ Weiter, aber in Phase 3 größeres Modell (whisper-small-Feintuning) prüfen |
| Trefferquote < 60 % | ❌ Erst Ursache klären (Details-CSV: liegt es an Erkennung oder Suche?) |

**Bitte nach dem Lauf `results/report.md` und `results/details.csv` hier
im Chat teilen** – dann werte ich aus und lege die Parameter für die App fest.

## Dateien

| Datei | Zweck |
|---|---|
| `quran_corpus.py` | Tanzil-Text laden, arabischen Text normalisieren |
| `quran_matcher.py` | Verssuche (Vorlage für die Swift-Version in Phase 2) |
| `fetch_data.py` | Korantext + Testset herunterladen |
| `transcribe.py` | Modelle laufen lassen, Transkripte cachen |
| `evaluate.py` | Trefferquoten, Schwellen, Bericht |
| `tests/test_matcher.py` | Tests der Verssuche mit künstlichen Fehlern |

## Quellen & Lizenzen

- Korantext: [Tanzil.net](https://tanzil.net) – CC BY 3.0, unverändert verwendet
- Testaudio: [EveryAyah.com](https://everyayah.com) – nur lokal zum Testen
- Modelle: [Tarteel AI auf Hugging Face](https://huggingface.co/tarteel-ai) – Apache 2.0
