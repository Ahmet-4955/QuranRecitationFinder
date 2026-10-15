# Claude-Code-Mods

Eingerichtet am 2026-10-15 nach dem Video
[„Diese 10 Claude Code Mods solltest du unbedingt kennen“](https://www.youtube.com/watch?v=ji4ANdb_M6Y)
von Julian Ivanov. Grundlage war die Videobeschreibung mit Links und Zeitstempeln.

Dieser Ordner ist ein Claude-Code-Marketplace namens `asm-claude-mods`. Bis auf
`cache-meter` zeigt jeder Eintrag auf das Original-Repo des jeweiligen Autors,
fremder Code liegt hier also nicht. `cache-meter` ist ein eigener Nachbau, weil das
Original nur als Prompt im Guide des Autors steht (die Seite war hier nicht erreichbar).

## Installieren (auf deinem Rechner)

Voraussetzung ist Claude Code **2.1.287 oder neuer** (`claude --version`, sonst `claude update`).

```bash
cd /pfad/zu/QuranRecitationFinder
./Tools/claude-mods/install-mods.sh           # alle 10
./Tools/claude-mods/install-mods.sh filetree  # oder nur einzelne
```

Danach in einer offenen Session `/reload-plugins` ausführen, sonst sind die Mods ab dem nächsten Start aktiv.
Sie werden für deinen Benutzer installiert und wirken damit in **allen** Projekten, nicht nur in diesem.

Der Marketplace wird über den lokalen Pfad dieses Ordners registriert. Wenn du das Repo
verschiebst, das Skript einfach noch einmal ausführen.

## Die 10 Mods

| # | Mod | Was er macht | Bedienung / Hinweis |
|---|-----|--------------|---------------------|
| 1 | `savvy-progress` | Fortschrittsbalken über dem Prompt und ein Panel mit allen Subagenten | `/agents-info`. Gebaut für den Skill savvy-flow, zeigt aber jeden Subagenten |
| 2 | `next-steps` | Schlägt nach jeder Antwort 2–3 nächste Prompts vor | Im leeren Prompt `1`/`2`/`3` übernimmt, `0` verwirft |
| 3 | `filetree` | Dateibaum in der Seitenleiste, zeigt, wo Claude liest und schreibt | Im Terminal braucht er `/tui fullscreen` und mindestens 110 Spalten. Wieder öffnen mit `/filetree` |
| 4 | `cache-meter` | Band über dem Prompt: Cache gelesen / geschrieben / ungecacht, Trefferquote, Restzeit bis der Cache kalt ist | `/cache-meter` blendet ein/aus. TTL einstellbar: `/plugin configure cache-meter@asm-claude-mods` (60 oder 5 Minuten) |
| 5 | `cache-tax` | Hält den 1-Stunden-Cache in Pausen warm und stoppt einmal einen „kalten“ Send mit Kostenschätzung | `/keepwarm`, `/keepwarm 90m`, `/keepwarm off`. **Achtung: Das Warmhalten verbraucht Tokens** |
| 6 | `visible-compact` | Zeigt den Verlauf vor und nach `/compact` nebeneinander | `/show-last-compact` |
| 7 | You Should Know | Ein Seitenagent weist dich auf Dinge hin, die du vielleicht übersehen hast | Eingebaut, wird nur eingeschaltet: `/plugin enable cc-plugin-you-should-know@builtin` |
| 8 | `catch-me-up` | Seitenleiste mit laufender Zusammenfassung der Session | Hilft, wenn du nach einer Pause wieder einsteigst |
| 9 | `replay-theater` (Anthropic) | Geht die Datei-Änderungen der letzten Runde Diff für Diff durch | `/replay` |
| 10 | `blast-radius` (Anthropic) | Hält riskante Befehle an (`rm -rf`, Force-Push, `reset --hard`, Migrationen) und zeigt, was sie ändern würden | Buttons Proceed / Cancel |

## Wo Mods wirken

- **Terminal (`claude`) und Desktop-App (Code-Tab):** alles sichtbar.
- **VS-Code-Panel, `claude -p`, Cloud-Sessions auf claude.ai:** Die Hooks laufen, aber die
  Mods zeichnen nichts. Bänder, Seitenleisten und Buttons sieht man dort also nicht.
- **WSL-Sessions der Desktop-App:** Dort laden Mods gar nicht.

## Sicherheit

Ein Mod läuft mit deinen Rechten: Er kann Dateien lesen und schreiben, Prozesse starten und
ins Netz gehen. Die externen Mods kommen von ihren Autoren auf GitHub, bei jedem `update`
in der jeweils aktuellen Version. Wer das nicht möchte, prüft vor `claude plugin update` den Code im Original-Repo.

## Quellen

- Savvy Progress: https://github.com/JohnnyVizz/claude-kit/tree/main/plugins/savvy-progress
- Next Steps: https://github.com/hamzafer/claude-code-mods
- Filetree: https://github.com/data-goblin/claude-code-filetree
- Cache Tax: https://github.com/karanb192/cache-tax
- Visible Compact: https://github.com/nvsravank/visible-compact
- Catch Me Up: https://github.com/oliverow/catch-me-up
- Replay Theater / Blast Radius: https://github.com/anthropics/claude-code-playground/tree/main/claude-code/mods
- Offizielle Doku: https://code.claude.com/docs/en/plugins/mods/overview
