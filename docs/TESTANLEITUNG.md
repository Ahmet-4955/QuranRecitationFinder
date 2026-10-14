# Testanleitung App (Stand Phase 1–6)

Stand: 14.10.2026

Voraussetzung: `Tools/data/README.md` Schritte 1–3 erledigt (Daten + Vergleichsfälle erzeugt).

## 1. Automatische Tests (Xcode, ca. 1–3 Min.)

**Product → Test** (⌘U). Erwartet: alle Tests grün.

| Datei | Prüft |
|---|---|
| `QuranDataTests.swift` | Phase 1: Korantext, Übersetzungen, Normalisierung, Einstellungen |
| `VerseMatcherTests.swift` | Phase 2: Verssuche, Gleichstände, fremder Text, Vergleich mit Python |
| `RecognitionFlowTests.swift` | Phase 4: Ablauf Aufnahme → Erkennung → Verlauf (simuliertes Mikrofon) |
| `Phase5Tests.swift` | Phase 5: Konfigurationsdatei, Testprotokoll |
| `Phase6Tests.swift` | Phase 6: Stille-Erkennung, Früherkennung, Teilen |
| `AppSettingsTests.swift` | Einstellungen (Sprache, Höchstdauer) |
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
| 11 | Nach einem Ergebnis „Stimmt nicht“ → `2:255` eingeben | „als falsch vermerkt“ |
| 12 | Einstellungen → Testprotokoll → Exportieren → Teilen | JSON-Datei per AirDrop auf den Mac |
| 13 | Text eingeben: `اعوذ بالله من الشيطان الرجيم بسم الله الرحمن الرحيم يس والقران الحكيم` | Erkannt 36:1, Übereinstimmung > 90 % |
| 14 | Ergebnis → „Ganze Sure lesen“ | Sure öffnet, springt zum Vers, Vers hervorgehoben |
| 15 | Ergebnis → „Teilen“ → Notizen | Arabisch + Übersetzung + „Korantext: Tanzil.net · Übersetzung: …“ |
| 16 | Mit Spracherkennung: 5 s rezitieren/abspielen, dann still sein | Aufnahme endet nach ~2,5 s Ruhe; unter dem Ergebnis „automatisch beendet – Stille“ |
| 17 | Mit Spracherkennung: lange Rezitation abspielen (z. B. Yasin) | endet vor der Höchstdauer; „Früh erkannt nach x s“ |
| 18 | Einstellungen → beide Automatiken aus → Aufnahme | läuft bis zur Höchstdauer |
| 19 | iPhone-Sprache Deutsch (oder Einstellungen → „App-Sprache ändern“ → Sprache: Deutsch) | alle Texte Deutsch wie bisher, Tabs „Erkennen / Verlauf / Einstellungen“ |
| 20 | App-Sprache Türkçe | Tabs „Tanı / Geçmiş / Ayarlar“, Fehlermeldungen und Mikrofon-Abfrage Türkisch, Zahlen mit Komma („1,4 sn“) |
| 21 | App-Sprache English | Tabs „Recognize / History / Settings“, Mikrofon-Abfrage Englisch |

Auffälligkeiten (Darstellung, Tempo, Texte) bitte mit Nummer melden.

**Sprache schnell wechseln (ohne iPhone-Einstellungen):** Xcode → Product → Scheme → Edit Scheme → Run → Options → *App Language*. App-Sprache (Oberfläche) und Übersetzungssprache (Koran-Übersetzung, Einstellungen → Übersetzung) sind unabhängig voneinander.

**Texte ändern:** `QuranRecitationFinder/Localizable.xcstrings` in Xcode öffnen (Tabelle EN/DE/TR). Neue Texte im Code immer englisch schreiben, dann im Katalog DE und TR ergänzen. `python3 Tools/l10n/check_strings.py` (auch in der CI) meldet fehlende oder veraltete Einträge.

## Hinweis zu den Pegel-Schwellen (Punkt 16)

Die Stille-Erkennung nutzt feste Schwellen (Rezitation ab ≈ −27 dB, Ruhe unter ≈ −36 dB).
Stoppt die Aufnahme zu früh (leise Wiedergabe) oder nie (laute Umgebung), bitte melden –
die Werte lassen sich anpassen (`Core/Recording/SilenceDetector.swift`).
