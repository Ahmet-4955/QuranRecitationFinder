# Checkliste: Veröffentlichung im App Store

Stand: 14.10.2026 · Erst relevant, wenn die App privat zuverlässig läuft.

Diese Liste ist keine Rechtsberatung. Bei kommerzieller Nutzung die Bedingungen
der Quellen vorher direkt prüfen bzw. bestätigen lassen.

## 1. Lizenzen der Inhalte

| Bestandteil | Lizenz | Kommerziell? | Pflichten | Status |
|---|---|---|---|---|
| Korantext (Tanzil.net) | CC BY 3.0 | ja | unverändert; Quelle + Link tanzil.net sichtbar | ✅ in „Quellen & Lizenzen“ |
| Übersetzungen (QuranEnc.com) | eigene Bedingungen | **vorher anfragen** | unverändert; QuranEnc + Version nennen; aktuell halten; keine unpassende Werbung | ✅ Angaben vorhanden · ☐ schriftliche Bestätigung für Bezahl-App |
| Sprachmodell (Tarteel Whisper) | Apache 2.0 | ja | Lizenztext + ggf. NOTICE beilegen, Änderungen kennzeichnen (Umwandlung nach Core ML) | ☐ Volltext in die App |
| WhisperKit (argmax-oss-swift) | MIT | ja | Copyright-Hinweis + Lizenztext beilegen | ☐ Volltext in die App |
| OpenAI Whisper (Grundmodell) | MIT | ja | Copyright-Hinweis | ☐ Volltext in die App |

**Aufgabe:** In „Quellen & Lizenzen“ die vollständigen Lizenztexte (Apache 2.0, MIT) als
eigene Seiten ergänzen.

## 2. Apple-Vorgaben

| Punkt | Hinweis | Status |
|---|---|---|
| Apple Developer Program | 99 €/Jahr, Konto als Privatperson oder Firma | ☐ |
| App-ID / Bundle-ID | derzeit `de.ahmet.QuranRecitationFinder` | ✅ |
| Datenschutz-Angaben („Privacy Nutrition Label“) | **„Keine Daten erfasst“**: Aufnahme, Erkennung, Verlauf und Protokoll bleiben auf dem Gerät | ☐ in App Store Connect eintragen |
| Datenschutzerklärung (URL) | Pflicht, auch wenn keine Daten erfasst werden | ☐ Webseite |
| Mikrofon-Begründung | `NSMicrophoneUsageDescription` | ✅ vorhanden |
| App-Größe | Modell base ≈ 150 MB + App → über Mobilfunk evtl. Hinweis ab 200 MB | ☐ prüfen; ggf. tiny-Modell |
| Richtlinie 1.1 (religiöse Inhalte) | respektvoll, korrekt – Ergebnisse vorab von kundiger Person prüfen lassen | ☐ |
| Mindest-iOS | 17.0 | ✅ |

## 3. App-Qualität vor dem Einreichen

| Punkt | Status |
|---|---|
| App-Symbol (alle Größen) und Startbildschirm | ☐ |
| Oberfläche mehrsprachig (derzeit nur Deutsch) – String Catalog DE/TR/EN | ☐ |
| Bedienungshilfen: VoiceOver-Beschriftungen, Dynamic Type, Kontrast | ☐ |
| Test auf ältestem unterstütztem Gerät (Neural Engine, Tempo) | ☐ |
| Kalibrierung abgeschlossen (Phase 5): Präzision ≥ 95 % mit eigenen Aufnahmen | ☐ |
| Hinweis in der App: „Die Erkennung kann sich irren – bitte den Text prüfen.“ | ☐ |
| Testprotokoll-Export im Release ausblenden oder als „Diagnose“ kennzeichnen | ☐ |

## 4. Ablauf

1. TestFlight: Build hochladen, mit 5–10 Personen testen (verschiedene Rezitatoren, Geräte)
2. Rückmeldungen über das Testprotokoll einsammeln → `Tools/phase5/calibrate.py`
3. App Store Connect: Beschreibung DE/TR/EN, Screenshots (6,7″ und 6,1″), Kategorie „Bildung“ oder „Nachschlagewerke“
4. Einreichen; Prüfdauer meist 1–3 Tage
