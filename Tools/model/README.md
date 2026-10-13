# Phase 3 – Spracherkennung auf dem iPhone

Stand: 14.10.2026

**Ziel:** Das Tarteel-Whisper-Modell läuft offline auf dem iPhone (Core ML,
Neural Engine) und ersetzt den Platzhalter. Abnahme: Aufnahme → Text in < 3 s.

| Baustein | Version / Lizenz |
|---|---|
| Modell | `tarteel-ai/whisper-tiny-ar-quran` oder `-base-` – Apache 2.0 (Entscheidung aus Phase 0) |
| Umwandlung | whisperkittools (MIT), braucht macOS + Python 3.11 |
| Laufzeit | WhisperKit aus `argmax-oss-swift` 1.1.1 (MIT), ab iOS 16 |

Der Swift-Code ist schon im Projekt (`Core/Recognition/WhisperKitRecognizer.swift`)
und wird erst aktiv, wenn Paket **und** Modell eingebunden sind (Schritte 3–4).
Bis dahin baut die App wie bisher mit Platzhalter.

---

## Schritt 1 – whisperkittools einrichten (einmalig, ca. 10 Min.)

Eigene Umgebung, weil whisperkittools feste Versionen braucht (torch 2.5, transformers 4.53):

```bash
cd ~/Developer                      # beliebiger Ordner außerhalb des Repos
git clone https://github.com/argmaxinc/whisperkittools.git
cd whisperkittools
python3.11 -m venv .venv && source .venv/bin/activate
pip install -e .
whisperkit-generate-model -h        # Test: Hilfe muss erscheinen
```

## Schritt 2 – Modell umwandeln (5–20 Min.)

In **derselben** Umgebung, im Repo-Ordner:

```bash
cd <Pfad>/QuranRecitationFinder
python Tools/model/convert_model.py --size base     # oder --size tiny (Ergebnis Phase 0)
```

Ergebnis: `Models/WhisperModel/` mit

```
AudioEncoder.mlmodelc  TextDecoder.mlmodelc  MelSpectrogram.mlmodelc
config.json  generation_config.json  tokenizer.json  model-info.json  …
```

Das Skript ergänzt automatisch fehlende `alignment_heads` aus dem OpenAI-Grundmodell
(bekannter Stolperstein bei feinabgestimmten Modellen) und legt `tokenizer.json`
in den Ordner – damit braucht die App kein Internet.

> Der Ordner ist per `.gitignore` vom Repo ausgeschlossen (einzelne Dateien
> > 100 MB, GitHub-Limit). Auf einem anderen Mac Schritt 1–2 wiederholen.

## Schritt 3 – Modellordner in Xcode einbinden (einmalig, 1 Min.)

1. Xcode → **File → Add Files to "QuranRecitationFinder"…**
2. Ordner `Models/WhisperModel` auswählen
3. Optionen: **„Create folder references“** (blauer Ordner – *nicht* „Create groups“),
   Haken bei Target **QuranRecitationFinder**, „Copy items if needed“ **aus**
4. **Add**

> Wichtig: blauer Ordner. Bei „Groups“ würden die Dateien der drei `.mlmodelc`
> flach kopiert und kollidieren („Multiple commands produce …“).

## Schritt 4 – WhisperKit-Paket einbinden (einmalig, 2 Min.)

1. Xcode → **File → Add Package Dependencies…**
2. URL: `https://github.com/argmaxinc/argmax-oss-swift`
3. Dependency Rule: **Up to Next Major Version**, ab `1.1.1`
4. Produkt **WhisperKit** auswählen → Target **QuranRecitationFinder** → **Add Package**

## Schritt 5 – Testen

1. **⌘U** – zusätzlich zu Phase 1/2/4 laufen jetzt:
   - `RecognizerTests.swift`: Modellordner-Prüfung, Auswahl der Spracherkennung
   - `WhisperKitSmokeTests`: lädt das echte Modell, gibt die Ladezeit in der Konsole aus
2. **⌘R auf dem iPhone** (nicht Simulator – die Neural Engine gibt es nur auf dem Gerät):
   - Einstellungen → Status muss nach dem ersten Start auf **„bereit“** springen
     (erstes Laden bis ca. 1 Min., danach Sekunden)
   - Erkennen → Rezitation 8–12 s abspielen → Ergebnis prüfen
   - Unter dem Ergebnis steht **„Spracherkennung: x,x s“** → Ziel **< 3 s**
3. Die 20–30 eigenen Aufnahmen aus Phase 0 einmal per Lautsprecher abspielen und
   in der App erkennen lassen → Trefferquote notieren und mir schicken.

## Fehlerbilder

| Meldung | Ursache / Lösung |
|---|---|
| „Swift-Paket WhisperKit ist noch nicht eingebunden“ | Schritt 4 fehlt |
| „Modellordner „WhisperModel“ ist nicht in der App“ | Schritt 3 fehlt oder als gelbe Gruppe statt blauem Ordner |
| „Modellordner unvollständig, es fehlt: …“ | Schritt 2 erneut ausführen |
| `Number of outputs … 4 … 3` beim Umwandeln | `alignment_heads` fehlt – sollte das Skript beheben; sonst Ausgabe schicken |
| Torch-Fehler bei `pip install` | Python 3.13 statt 3.11 verwendet |
| Erkennung > 3 s | Release-Build testen (Product → Scheme → Run → Release); sonst tiny-Modell probieren |

## Tests des Skripts (offline)

```bash
python -m pytest -q Tools/model/tests
```
