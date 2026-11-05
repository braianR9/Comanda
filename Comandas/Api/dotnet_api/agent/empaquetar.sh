#!/bin/bash
# Arma los instaladores del agente de impresión que se descargan desde Foco > Impresoras.
# Uso: agent/empaquetar.sh <carpeta de salida> [url de la API]
# Deja FocoAgente-Windows.zip y FocoAgente-Mac.zip (Mac con Apple Silicon e Intel en el mismo zip).
set -euo pipefail
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
API_URL="${2:-https://api.focobr.net}"
AGENT="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for rid in win-x64 osx-arm64 osx-x64; do
  dotnet publish "$AGENT/FocoAgente/FocoAgente.csproj" -c Release -r "$rid" -o "$WORK/bin/$rid" -v quiet -nologo
done
printf '{\n  "apiUrl": "%s",\n  "clave": ""\n}\n' "$API_URL" > "$WORK/agente.json"

WIN="$WORK/FocoAgente-Windows"
mkdir -p "$WIN"
cp "$WORK/bin/win-x64/FocoAgente.exe" "$WORK/agente.json" "$AGENT"/windows/*.cmd "$WIN/"
# PowerShell de Windows lee los .ps1 sin BOM como ANSI: el BOM conserva los acentos.
for f in "$AGENT"/windows/*.ps1; do
  { printf '\xEF\xBB\xBF'; cat "$f"; } > "$WIN/$(basename "$f")"
done

MAC="$WORK/FocoAgente-Mac"
mkdir -p "$MAC"
cp "$WORK/bin/osx-arm64/FocoAgente" "$MAC/FocoAgente-arm64"
cp "$WORK/bin/osx-x64/FocoAgente" "$MAC/FocoAgente-x64"
cp "$WORK/agente.json" "$AGENT"/mac/*.command "$MAC/"
chmod +x "$MAC"/*

rm -f "$OUT/FocoAgente-Windows.zip" "$OUT/FocoAgente-Mac.zip"
(cd "$WORK" && zip -qr -X "$OUT/FocoAgente-Windows.zip" FocoAgente-Windows && zip -qr -X "$OUT/FocoAgente-Mac.zip" FocoAgente-Mac)
ls -lh "$OUT"/FocoAgente-*.zip
