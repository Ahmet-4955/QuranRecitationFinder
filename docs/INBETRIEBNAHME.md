# Inbetriebnahme – von null zur laufenden App auf dem iPhone

Stand: 14.10.2026 · Gesamtdauer kürzester Weg: ca. 1–1,5 Std. (davon viel Wartezeit)

Diese Anleitung fasst alle Phasen in der richtigen Reihenfolge zusammen.
Details stehen jeweils in der verlinkten README.

## Voraussetzungen

| Was | Hinweis |
|---|---|
| Mac mit Xcode 26 | vorhanden |
| iPhone mit iOS 17 oder neuer, Kabel | Neural Engine nötig – Simulator reicht nicht für die Spracherkennung |
| Homebrew | `brew --version`; sonst https://brew.sh |
| Apple-ID in Xcode (Settings → Accounts) | kostenloses Konto genügt; App läuft dann 7 Tage, danach neu aufspielen |
| ca. 5 GB freier Speicher | Modelle, Python-Umgebungen |

## Kürzester Weg (Schritte 1–6)

### 1. Repo und Grundwerkzeuge (10 Min.)

```bash
git clone https://github.com/Ahmet-4955/QuranRecitationFinder.git    # falls noch nicht vorhanden
cd QuranRecitationFinder
git checkout claude/sharp-hopper-olul31                             # bzw. main nach dem Merge
brew install python@3.11 ffmpeg
python3.11 -m venv .venv && source .venv/bin/activate
pip install -r Tools/phase0/requirements.txt
```

### 2. Korantext und Übersetzungen erzeugen (5 Min.) – Phase 1

```bash
python Tools/data/build_resources.py --list tr      # optional: türkische Übersetzung wählen
python Tools/data/build_resources.py                # oder: --tr <key>
python Tools/phase0/export_swift_fixtures.py        # Vergleichsfälle Swift ↔ Python
git add QuranRecitationFinder/Resources QuranRecitationFinderTests/MatcherFixtures.swift
git commit -m "data: add Tanzil text, QuranEnc translations and matcher fixtures" && git push
```

### 3. In Xcode bauen und testen (10 Min.)

1. `QuranRecitationFinder.xcodeproj` öffnen
2. Target **QuranRecitationFinder** → **Signing & Capabilities** → Team = Ihre Apple-ID
3. **⌘U** – alle Tests müssen grün sein
4. Fehlermeldungen → Text kopieren und im Chat schicken

> Ab hier läuft die App schon: **⌘R** auf dem iPhone, „Text eingeben“ testet die Verssuche
> mit Übersetzung (Checkliste: `docs/TESTANLEITUNG.md`). Nur das Mikrofon meldet noch
> „Spracherkennung nicht verfügbar“.

### 4. Sprachmodell umwandeln (20–30 Min., davon ~15 Min. warten) – Phase 3

Eigene Umgebung mit Python 3.11 (Details: `Tools/model/README.md`):

```bash
deactivate 2>/dev/null; cd ~/Developer
git clone https://github.com/argmaxinc/whisperkittools.git && cd whisperkittools
python3.11 -m venv .venv && source .venv/bin/activate && pip install -e .
cd <Pfad>/QuranRecitationFinder
python Tools/model/convert_model.py --size base
```

> **tiny oder base?** Ohne Phase-0-Messung: **base** nehmen (genauer, ~150 MB).
> Ist base auf dem iPhone zu langsam (> 3 s), später tiny umwandeln.

### 5. Modell und WhisperKit in Xcode einbinden (5 Min.)

1. **File → Add Files…** → `Models/WhisperModel` → **„Create folder references“** (blauer Ordner), Target ✓
2. **File → Add Package Dependencies…** → `https://github.com/argmaxinc/argmax-oss-swift`
   → „Up to Next Major“ ab 1.1.1 → Produkt **WhisperKit** → Target ✓

### 6. Auf dem iPhone starten (10 Min.)

1. iPhone verbinden, als Ziel wählen, **⌘R**
2. Beim ersten Start: Einstellungen → Status wechselt nach bis zu 1 Min. auf **„bereit“**
3. Rezitation 8–12 s abspielen (Lautsprecher, TV, zweites Handy) → **Mikrofon-Button**
4. Ergebnis prüfen, **„Stimmt / Stimmt nicht“** antippen, unten steht die Erkennungszeit

**✅ Damit läuft die App vollständig.**

## Feinabstimmung (Phase 0 + 5, wenn Zeit ist)

### 7. Messung auf dem Mac (1–2 Std. inkl. Aufnahmen) – Phase 0

Siehe `Tools/phase0/README.md`: Testset laden, 20–30 eigene Aufnahmen machen, auswerten.

```bash
source .venv/bin/activate
python Tools/phase0/fetch_data.py
python Tools/phase0/transcribe.py && python Tools/phase0/evaluate.py
```

### 8. Schwelle kalibrieren (5 Min.) – Phase 5

1. App → Einstellungen → Testprotokoll → **Exportieren** → per AirDrop auf den Mac
2. ```bash
   python Tools/phase5/calibrate.py \
     --phase0 Tools/phase0/results/details.csv --model tarteel-ai/whisper-base-ar-quran \
     --app ~/Downloads/testprotokoll-*.json
   ```
3. Das Skript schreibt `QuranRecitationFinder/Resources/recognition-config.json`
   → App neu bauen → committen

Je mehr bewertete Erkennungen (Ziel ≥ 50), desto verlässlicher die Schwelle.

## Automatische Prüfung

Bei jedem Push prüft GitHub automatisch (`.github/workflows/ci.yml`):

- alle Python-Werkzeuge (31 Tests)
- den App-Kern mit Swift 6.2: kompilieren + Swift-Tests (Linux, ohne Oberfläche)

Rotes Kreuz im Pull Request → Details anklicken oder im Chat melden.
Lokal dasselbe: `Tools/linux-check/run.sh` (braucht Docker).

## Wenn etwas hakt

| Problem | Wo nachsehen |
|---|---|
| Daten-Download bricht ab | `Tools/data/README.md` |
| Xcode-Build-Fehler | Meldung schicken |
| Modell-Umwandlung | `Tools/model/README.md` → Fehlerbilder |
| Erkennung falsch/unsicher | Testprotokoll exportieren + schicken |
