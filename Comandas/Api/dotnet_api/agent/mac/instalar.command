#!/bin/bash
# Instala el agente de impresión de Foco en esta Mac (doble clic).
# Lo copia a ~/FocoAgente y lo deja arrancando solo al iniciar sesión (LaunchAgent).
cd "$(dirname "$0")" || exit 1
DEST="$HOME/FocoAgente"
LABEL="net.focobr.agente"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

echo ""
echo "Agente de impresión de Foco"
echo "---------------------------"
read -r -p "Pegá la clave del agente (la generás en Foco > Impresoras) y apretá Enter: " CLAVE
CLAVE="$(echo "$CLAVE" | tr -d '[:space:]')"
if [ -z "$CLAVE" ]; then
  echo "No ingresaste la clave. No se instaló nada."
  read -r -p "Enter para cerrar"
  exit 1
fi

case "$(uname -m)" in
  arm64) BIN="FocoAgente-arm64" ;;
  *) BIN="FocoAgente-x64" ;;
esac
API_URL="$(sed -n 's/.*"apiUrl": *"\([^"]*\)".*/\1/p' agente.json)"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
mkdir -p "$DEST" "$HOME/Library/LaunchAgents"
cp "$BIN" "$DEST/FocoAgente"
cp desinstalar.command "$DEST/"
chmod +x "$DEST/FocoAgente" "$DEST/desinstalar.command"
# Descargado de internet: se quita la cuarentena y se firma localmente para que macOS lo deje correr.
xattr -cr "$DEST" 2>/dev/null
codesign --force -s - "$DEST/FocoAgente" >/dev/null 2>&1
printf '{\n  "apiUrl": "%s",\n  "clave": "%s"\n}\n' "$API_URL" "$CLAVE" > "$DEST/agente.json"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$DEST/FocoAgente</string></array>
  <key>WorkingDirectory</key><string>$DEST</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$DEST/agente.log</string>
  <key>StandardErrorPath</key><string>$DEST/agente.log</string>
</dict>
</plist>
EOF
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo ""
echo "Listo: el agente quedó instalado en $DEST y arranca solo al iniciar sesión."
echo ""
echo "Impresoras de esta Mac. En Foco, el \"Nombre de la cola\" de cada impresora"
echo "tiene que ser igual a uno de estos nombres:"
lpstat -a 2>/dev/null | awk '{print "  - " $1}'
echo ""
echo "Registro del agente: $DEST/agente.log"
read -r -p "Enter para cerrar"
