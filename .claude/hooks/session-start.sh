#!/bin/bash
# Installiert Ghidra 12.1.4 und registriert den REA-MCP-Server (rea-agents) fuer Claude Code.
# Nur in Cloud-Sessions, idempotent, nicht-interaktiv.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

VER=12.1.4
DATE=20260921
SHA=ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db
DIR="/opt/ghidra/ghidra_${VER}_PUBLIC"

if [ ! -x "$DIR/support/analyzeHeadless" ]; then
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  curl -fsSL -o "$TMP/ghidra.zip" \
    "https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_${VER}_build/ghidra_${VER}_PUBLIC_${DATE}.zip"
  echo "$SHA  $TMP/ghidra.zip" | sha256sum -c -
  mkdir -p /opt/ghidra
  unzip -q "$TMP/ghidra.zip" -d /opt/ghidra
fi

export GHIDRA_INSTALL_DIR="$DIR"
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export GHIDRA_INSTALL_DIR=\"$DIR\"" >> "$CLAUDE_ENV_FILE"
fi

# REA-MCP-Registrierung + Skill (schreibt nach ~/.claude.json und ~/.claude/skills)
(cd /tmp && npx --yes rea-agents setup --client claude_code --yes >/dev/null)
echo "Ghidra $VER + REA bereit: $DIR"
