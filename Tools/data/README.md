# Phase 1 – Datenbasis

Stand: 13.10.2026

Erzeugt die Daten, die fest in die App eingebaut werden:

| Inhalt | Quelle | Datei in `QuranRecitationFinder/Resources/` |
|---|---|---|
| Korantext Uthmani (Anzeige) | Tanzil.net | `Quran/quran-uthmani.xml` |
| Korantext Simple Clean (Verssuche) | Tanzil.net | `Quran/quran-simple-clean.xml` |
| Surennamen, Versanzahl | Tanzil.net | `Quran/quran-data.xml` |
| Übersetzung Deutsch | QuranEnc.com | `Translations/translation-<key>.json` |
| Übersetzung Türkisch | QuranEnc.com | `Translations/translation-<key>.json` |
| Übersetzung Englisch | QuranEnc.com | `Translations/translation-<key>.json` |
| Verzeichnis der Übersetzungen | – | `Translations/translations-index.json` |
| Quellen & Lizenzen | – | `SOURCES.md` |

Inhalte werden **unverändert** übernommen (Lizenzbedingungen Tanzil + QuranEnc).

## Schritt 1 – Übersetzungen auswählen (optional)

Voreingestellt: Deutsch `german_bubenheim`, Englisch `english_saheeh`,
Türkisch `turkish_rwwad` (sonst `turkish_shaban`). Alle Optionen anzeigen:

```bash
cd Tools/phase0 && source .venv/bin/activate   # Umgebung aus Phase 0 nutzen
cd ../data
python build_resources.py --list tr
python build_resources.py --list de
```

> Hinweis: Die Diyanet-Übersetzung ist nach meinem Kenntnisstand nicht frei
> verfügbar und daher vermutlich nicht bei QuranEnc – `--list tr` zeigt, was es gibt.

## Schritt 2 – Ressourcen erzeugen (ca. 3–5 Min.)

```bash
python build_resources.py
# oder mit eigener Wahl:
python build_resources.py --tr turkish_shaban
```

Das Skript bricht ab, wenn etwas unvollständig ist (z. B. fehlender Vers).

## Schritt 3 – In Xcode prüfen

1. Projekt öffnen – die neuen Dateien unter `Resources/` erscheinen automatisch
   (synchronisierte Ordner).
2. **Product → Test** (⌘U). Die Phase-1-Abnahmetests stehen in
   `QuranRecitationFinderTests/QuranDataTests.swift`:
   - 114 Suren, 6.236 Verse, jeder Vers mit Text (beide Tanzil-Ausgaben)
   - Übersetzung DE/TR/EN jeweils vollständig, mit Versionsnummer
   - Normalisierung identisch zum Python-Prototyp aus Phase 0
   - Spracheinstellung wird gespeichert, Standard folgt der Gerätesprache
3. Bei grünen Tests: Ressourcen committen.

```bash
cd ../..
git add QuranRecitationFinder/Resources
git commit -m "data: add Tanzil text and QuranEnc translations"
git push
```

## Tests des Skripts selbst (offline)

```bash
python -m pytest -q tests
```
