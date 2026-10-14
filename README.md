# Quran Recitation Finder

iOS-App: Ausschnitt einer Koranrezitation aufnehmen → die App zeigt Sure und Vers
und die Übersetzung (Deutsch, Türkisch oder Englisch). Läuft komplett offline.

**So funktioniert es**

1. Aufnahme (16 kHz) → **Tarteel Whisper** (auf Koranrezitation trainiert) wandelt sie
   per WhisperKit auf dem iPhone in arabischen Text um
2. **Verssuche** findet den Text im gesamten Koran (6.236 Verse) – fehlertolerant,
   auch über Versgrenzen, gleichlautende Stellen werden alle genannt
3. Anzeige in Uthmani-Schrift mit Übersetzung von QuranEnc

**Loslegen:** [`docs/INBETRIEBNAHME.md`](docs/INBETRIEBNAHME.md)

| Dokument | Inhalt |
|---|---|
| [`docs/PLAN.md`](docs/PLAN.md) | Technologieentscheidung, Phasen, Stand |
| [`docs/INBETRIEBNAHME.md`](docs/INBETRIEBNAHME.md) | Schritt für Schritt zur laufenden App |
| [`docs/TESTANLEITUNG.md`](docs/TESTANLEITUNG.md) | Tests in Xcode und auf dem iPhone |
| `Tools/*/README.md` | Werkzeuge je Phase |

## Aufbau

```
QuranRecitationFinder/
  App/         Start, Laden, Tabs
  Core/        Quran (Text), Matching (Verssuche), Translation, Recognition (WhisperKit),
               Audio, History, Feedback, Settings
  Features/    Erkennen, Ergebnis, Verlauf, Einstellungen
  Resources/   Korantext, Übersetzungen, recognition-config.json
Tools/
  phase0/      Machbarkeitstest + Verssuche-Prototyp (Python)
  data/        Korantext + Übersetzungen erzeugen
  model/       Whisper-Modell für Core ML umwandeln
  phase5/      Schwelle kalibrieren
  linux-check/ App-Kern mit Swift 6.2 in Docker prüfen
```

## Quellen und Lizenzen

- Korantext: [Tanzil.net](https://tanzil.net) – CC BY 3.0, unverändert
- Übersetzungen: [QuranEnc.com](https://quranenc.com) – unverändert, mit Versionsangabe
- Sprachmodell: [Tarteel AI](https://huggingface.co/tarteel-ai) – Apache 2.0
- WhisperKit: [argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift) – MIT
