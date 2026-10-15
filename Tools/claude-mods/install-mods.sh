#!/usr/bin/env bash
# Installiert die 10 Claude-Code-Mods aus dem Video "Diese 10 Claude Code Mods
# solltest du unbedingt kennen" (Julian Ivanov) für deinen Benutzer (alle Projekte).
# Voraussetzung: Claude Code 2.1.287 oder neuer (`claude --version`, sonst `claude update`).
#
# Aufruf:  ./Tools/claude-mods/install-mods.sh            alle Mods
#          ./Tools/claude-mods/install-mods.sh filetree    nur die genannten
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKET="asm-claude-mods"
ALL=(savvy-progress next-steps filetree cache-meter cache-tax visible-compact catch-me-up replay-theater blast-radius)
MODS=("${@:-${ALL[@]}}")

command -v claude >/dev/null || { echo "claude nicht gefunden: erst Claude Code installieren." >&2; exit 1; }
echo "Claude Code $(claude --version)"

if claude plugin marketplace list 2>/dev/null | grep -q "$MARKET"; then
  claude plugin marketplace update "$MARKET"
else
  claude plugin marketplace add "$HERE"
fi

for m in "${MODS[@]}"; do
  echo "--- $m"
  claude plugin install "$m@$MARKET" --scope user
done

# Mod 7 ist in Claude Code eingebaut und muss nur eingeschaltet werden.
if [ "$#" -eq 0 ]; then
  echo "--- you-should-know (eingebaut)"
  claude plugin enable cc-plugin-you-should-know@builtin || \
    echo "Hinweis: 'You should know' ist für dein Konto/deine Verbindung nicht verfügbar."
fi

echo
echo "Fertig. In einer offenen Session: /reload-plugins  (sonst beim nächsten Start aktiv)."
