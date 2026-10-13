# Testanleitung App (Stand Phase 1–4)

Stand: 14.10.2026

Voraussetzung: `Tools/data/README.md` Schritte 1–3 erledigt (Daten + Vergleichsfälle erzeugt).

## 1. Automatische Tests (Xcode, ca. 1–3 Min.)

**Product → Test** (⌘U). Erwartet: alle Tests grün.

| Datei | Prüft |
|---|---|
| `QuranDataTests.swift` | Phase 1: Korantext, Übersetzungen, Normalisierung, Einstellungen |
| `VerseMatcherTests.swift` | Phase 2: Verssuche, Gleichstände, fremder Text, Vergleich mit Python |
| `RecognitionFlowTests.swift` | Phase 4: Ablauf Aufnahme → Erkennung → Verlauf (simuliertes Mikrofon) |
| `RecognizerTests.swift` | Phase 3: Modellordner, Auswahl Spracherkennung, Rauchtest mit echtem Modell (nur wenn eingebunden) |

Bei Fehlern: Meldung aus dem Test-Navigator (⌘6) kopieren und im Chat schicken.

## 2. App auf dem iPhone (ca. 10 Min.)

iPhone per Kabel verbinden, als Ziel wählen, **Run** (⌘R).

| # | Schritt | Erwartung |
|---|---|---|
| 1 | App starten | kurz „Korantext wird geladen …“, dann Tab „Erkennen“ |
| 2 | Oben rechts „Text eingeben“ → `قل هو الله احد` → Suchen | „Erkannt“, 112. Al-Ikhlaas · 112:1, arabischer Text rechtsbündig + Übersetzung |
| 3 | Text eingeben: `فباي الاء ربكما تكذبان` | Erkannt in Sure 55, darunter „Gleicher Wortlaut auch in:“ mit weiteren Stellen |
| 4 | Text eingeben: `اهدنا الصراط المستقيم صراط الذين انعمت عليهم` | Bereich 1:6–1:7, beide Verse mit Übersetzung |
| 5 | Text eingeben: beliebiger moderner arabischer Satz | „Nicht sicher erkannt“ oder „Kein Koranvers erkannt“ |
| 6 | Tab „Einstellungen“ → Sprache auf Türkçe → zurück zu einem Ergebnis | Übersetzung jetzt Türkisch |
| 7 | Tab „Verlauf“ | erkannte Einträge aus 2–4 (nicht 5), Wischen zum Löschen |
| 8 | Mikrofon-Button antippen | Mikrofon-Abfrage; Kreis pulsiert mit Lautstärke, Sekunden zählen |
| 9 | Nach > 2 s Stopp | ohne Phase 3: Hinweis „Spracherkennung nicht verfügbar (Phase 3)“ – **erwartet**; mit Phase 3: Ergebnis + „Spracherkennung: x,x s“ (Ziel < 3 s) |
| 10 | Einstellungen → Quellen & Lizenzen | Tanzil + drei Übersetzungen mit Version |

Auffälligkeiten (Darstellung, Tempo, Texte) bitte mit Nummer melden.
