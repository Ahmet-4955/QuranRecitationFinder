# QuranRecitationFinder – Neuplanung

Stand: 13.10.2026

## Ziel

iOS-App: Ausschnitt einer Koranrezitation aufnehmen → App zeigt Sure und Vers
(bzw. Versbereich) → dazu die Übersetzung in der voreingestellten Sprache.

Anforderungen:

- Erkennung über den gesamten Koran (114 Suren, 6.236 Verse)
- Ausschnitte mitten aus einem Vers und über Versgrenzen hinweg
- Offline-fähig (keine Serverkosten, kein Datenschutzproblem)
- Ehrliches „nicht erkannt“ statt Ratetreffer
- Übersetzung wählbar (z. B. Deutsch, Türkisch, Englisch)

## Bewährtes Grundprinzip

Alle funktionierenden Lösungen (Tarteel, offline-tarteel, QV-Finder-Paper,
diverse Open-Source-Tracker) arbeiten zweistufig:

1. **Rezitation → arabischer Text**: ein speziell auf Koranrezitation
   trainiertes Spracherkennungsmodell.
2. **Text → Vers**: unscharfe Suche (Fuzzy-Matching) des erkannten Texts im
   vollständigen Korantext.

Ein Audio-Fingerabdruck (Shazam-Prinzip) scheidet aus: Er erkennt nur
*dieselbe Aufnahme* wieder, nicht denselben Vers von einem anderen Rezitator.
Apples Spracherkennung scheidet ebenfalls aus: nicht für Tajwid trainiert, und
die neue `SpeechAnalyzer`-API (iOS 26) unterstützt Arabisch laut Berichten
bislang nicht.

## Technologieentscheidung

### Stufe 1: Spracherkennung (Kandidaten)

| | A: Tarteel Whisper + WhisperKit | B: Quran-Lab Zipformer + ONNX Runtime |
|---|---|---|
| Modell | `tarteel-ai/whisper-base-ar-quran` (oder `-tiny-`) | `zipformer_p-arabic-v3` (wie in offline-tarteel) |
| Lizenz | Apache 2.0 – auch kommerziell nutzbar | NPL-1.2 – **nicht kommerziell**, Share-Alike |
| Ausgabe | Arabischer Text | Tajwid-Phoneme |
| Größe | ca. 75–150 MB (je nach Quantisierung) | ca. 66 MB (int8) + 5,5 MB Korpus |
| Gemeldete Qualität | WER ca. 5–7 % (Modellkarte) | 100 % Verstreffer auf 53 Testclips, PER 3,6 % |
| iOS-Integration | WhisperKit (Swift, Core ML, Neural Engine) – Standardweg | onnxruntime (Swift Package) + eigene CTC-Dekodierung |
| Aufwand | gering bis mittel (Modell nach Core ML konvertieren) | mittel bis hoch |

**Empfehlung: A als Hauptweg.** Saubere Lizenz, Swift-nativ, gut dokumentiert.
B nur, wenn A im Test schlecht abschneidet **und** die App nicht kommerziell
vertrieben wird.

### Stufe 2: Vers-Suche (eigene Implementierung, Swift)

1. Korantext als **eine durchgehende Wortfolge** (~77.400 Wörter), jedes Wort
   mit Sure:Vers verknüpft.
2. **Normalisierung** für Vergleich: Vokalzeichen/Tatweel entfernen,
   Alif-Varianten (أ إ آ ٱ → ا), ى → ي, ة → ه vereinheitlichen.
3. **Kandidatensuche**: Index über Wort-Trigramme → Stellen im Koran, an denen
   mehrere Trigramme des erkannten Texts vorkommen.
4. **Feinabgleich**: lokale Alignierung (Smith-Waterman auf Wortebene,
   Wortvergleich per Levenshtein-Ähnlichkeit) um jeden Kandidaten.
5. **Ergebnis**: bester Treffer als Versbereich (z. B. 2:255–2:256) mit
   Trefferquote 0–100 %. Unter Schwelle (Startwert 60 %, per Test
   kalibriert) → „Nicht sicher erkannt“, ggf. Top-3 zur Auswahl.
6. Laufzeit: Millisekunden auf dem iPhone, kein Server.

### Daten

| Inhalt | Quelle | Bedingungen |
|---|---|---|
| Korantext Anzeige | Tanzil – Uthmani | CC BY 3.0, unverändert, Quelle + Link tanzil.net nennen |
| Korantext Vergleich | Tanzil – Simple Clean | wie oben; Normalisierung erst zur Laufzeit |
| Übersetzungen | QuranEnc.com (z. B. Deutsch Bubenheim/Elyas, Türkisch, Englisch Saheeh) | unverändert, QuranEnc + Versionsnummer nennen, aktuell halten, keine unpassende Werbung |
| Surennamen/Metadaten | Tanzil Metadata | CC BY 3.0 |

Alles wird **gebündelt in der App** ausgeliefert (SQLite oder JSON, wenige MB),
keine Online-Abhängigkeit.

### Audio

- `AVAudioEngine`, direkt 16 kHz mono Float32 (Whisper-Eingangsformat)
- Aufnahme 5–15 s, automatischer Stopp bei Stille (VAD) oder per Taste
- Später optional: Live-Erkennung während der Aufnahme

## App-Architektur (SwiftUI, iOS 17+)

```
QuranRecitationFinder/
├── App/                 App-Einstieg, Navigation
├── Audio/               AudioCaptureService (AVAudioEngine, 16 kHz)
├── Recognition/         RecognitionEngine (Protokoll)
│                        └── WhisperKitEngine (Variante A)
├── Corpus/              QuranCorpus (Text, Metadaten, Wortindex)
├── Matching/            Normalizer, CandidateIndex, Aligner, VerseMatcher
├── Translation/         TranslationStore (gebündelte Übersetzungen)
├── Settings/            Sprache/Übersetzung, Schwelle, Aufnahmedauer
├── UI/                  RecordView, ResultView, SettingsView, HistoryView
└── Resources/           Korantext, Übersetzungen, Lizenzhinweise
Tools/                   Python-Skripte: Modellkonvertierung, Daten-Import, Testauswertung
```

Das Erkennungsmodell steckt hinter einem Protokoll → Variante A/B austauschbar,
ohne die App umzubauen.

## Umsetzungsplan

| Phase | Inhalt | Ergebnis / Abnahme |
|---|---|---|
| **0. Machbarkeitstest (Mac)** | Python: Tarteel-Whisper (tiny + base) auf 30–50 eigenen Testclips (verschiedene Rezitatoren, eigene Stimme, Handy-Mikrofon, Hintergrundgeräusch) laufen lassen, Vers-Suche als Prototyp | Trefferquote je Modell; Entscheidung A/B und tiny/base |
| **1. Datenbasis** | Tanzil-Text + Metadaten + QuranEnc-Übersetzungen importieren, Corpus- und Translation-Store in Swift | Unit-Tests: 6.236 Verse geladen, jede Übersetzung vollständig |
| **2. Vers-Suche** | Normalizer, Trigramm-Index, Alignierung, Schwelle | Unit-Tests: Textausschnitte (mit eingebauten Fehlern) → richtiger Vers ≥ 95 % |
| **3. Spracherkennung** | Modell nach Core ML konvertieren (whisperkittools), WhisperKit einbinden, AudioCaptureService | Auf dem iPhone: Aufnahme → Text in < 3 s |
| **4. Oberfläche** | Aufnahme, Ergebnis (Arabisch + Übersetzung), Einstellungen, Verlauf, Lizenzhinweise | Durchgängiger Ablauf auf echtem Gerät |
| **5. Kalibrierung** | Testset aus Phase 0 in der App, Schwelle einstellen, Grenzfälle (sehr kurze Ausschnitte, gleichlautende Verse) | Trefferquote dokumentiert, Fehlalarme < 5 % |
| **6. Ausbau (optional)** | Live-Erkennung, Abspielen der Referenzrezitation, Tafsir, weitere Sprachen | – |

Phase 0 ist der wichtigste Schritt: Sie klärt mit echten Zahlen, ob das Modell
für eigene Aufnahmen (nicht nur Studio-Rezitationen) gut genug ist, bevor Zeit
in die App fließt.

## Stand der Phasen

| Phase | Stand (13.10.2026) |
|---|---|
| 0 | Werkzeuge fertig (`Tools/phase0/`), Verssuche getestet. **Messung mit echten Modellen + eigenen Aufnahmen steht aus (Mac).** |
| 1 | Vorbereitet: Ressourcen-Skript (`Tools/data/`), Swift-Datenschicht (`QuranRecitationFinder/Core/`), Abnahmetests. **Daten erzeugen + Tests in Xcode ausführen steht aus (Mac).** |
| 2 | Vorbereitet: Swift-Verssuche (`Core/Matching/`), Schwelle 0,6 (vorläufig) + Gleichstand-Erkennung, Abnahmetests, Vergleichsfälle-Export. Logik in Python-Nachbau mit Prototyp abgeglichen (154/154 identisch). **Kompilieren + Tests in Xcode steht aus (Mac); Schwelle nach Phase 0 kalibrieren.** |
| 4 | Vorbereitet: neue Oberfläche (Erkennen / Verlauf / Einstellungen / Quellen & Lizenzen), Aufnahme über AVAudioEngine direkt in 16 kHz, Spracherkennung hinter Protokoll `RecitationRecognizer` (Platzhalter bis Phase 3), Texteingabe zum Testen, Ablauftests mit simuliertem Mikrofon. Alter Code entfernt. **Kompilieren + Gerätetest steht aus (Mac), Anleitung: `docs/TESTANLEITUNG.md`.** |

## Umgang mit dem bestehenden Code

- Neuaufbau mit obiger Struktur.
- Übernommen werden nur: Mikrofonberechtigung, Grundidee Feedback, Info.plist-Texte.
- Entfernt werden: Apple-Spracherkennung, Audio-Fingerprint, Sample-JSON,
  Download ganzer Suren, fehlerhafte Punkteskala.
- `Package.swift` wird entfernt (Xcode-Projekt ist maßgeblich) oder korrigiert.

## Entscheidungen

| Datum | Entscheidung |
|---|---|
| 13.10.2026 | Vorerst privat, später ggf. kommerziell → nur kommerziell nutzbare Lizenzen. **Variante A (Tarteel Whisper, Apache 2.0)**; Variante B (NPL, nicht kommerziell) entfällt. |
| 13.10.2026 | Übersetzungen zum Start: **Deutsch, Türkisch, Englisch** |
| 13.10.2026 | Mindestversion **iOS 17** |
| offen | Modellgröße tiny vs. base → entscheidet Phase 0 (`Tools/phase0/`) |

## Risiken

| Risiko | Gegenmaßnahme |
|---|---|
| Modell schwach bei Laien-Stimme / Handy-Mikrofon / Hall | Phase 0 misst genau das; ggf. größeres Modell oder Variante B |
| Sehr kurze Ausschnitte (1–3 Wörter) mehrdeutig | Mindestlänge empfehlen, Top-3 anzeigen |
| Wiederholte Verse (z. B. 55:13 „Fabi-ayyi ālāʾi …“ 31×) | Alle Fundstellen anzeigen statt einer |
| Lizenzbedingungen der Übersetzungen ändern sich | Quellen + Versionen in Resources dokumentieren, vor Veröffentlichung prüfen |
| Konvertierung Whisper → Core ML hakt | Bekannte Stolpersteine: Python ≤ 3.12, config.json manuell kopieren, Alignment-Heads aus Basismodell |

## Quellen

- Tarteel-Modelle: https://huggingface.co/tarteel-ai/whisper-base-ar-quran, https://huggingface.co/tarteel-ai/whisper-tiny-ar-quran
- WhisperKit: https://github.com/argmaxinc/WhisperKit
- offline-tarteel (Zipformer, Lizenzen): https://github.com/yazinsai/offline-tarteel
- QV Finder (Paper): https://ijeecs.iaescore.com/index.php/IJEECS/article/view/42402
- Tanzil Lizenz: https://tanzil.net/docs/license
- QuranEnc (Übersetzungen, API): https://quranenc.com
- Quran Foundation Developer Terms: https://api-docs.quran.foundation/legal/developer-terms/
- SpeechAnalyzer & Arabisch (Apple-Forum): https://developer.apple.com/forums/thread/797835
