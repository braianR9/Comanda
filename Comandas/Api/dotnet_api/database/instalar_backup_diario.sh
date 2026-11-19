#!/bin/bash
# Programa el backup de la base todos los días (por defecto a las 12:00) en esta Mac. También corre al
# iniciar sesión: si la Mac estuvo apagada a esa hora, el backup del día se hace al prenderla.
# A esa hora la base suele estar despierta por el uso de los locales: el backup no suma cómputo en Neon.
#
# Uso:   ./instalar_backup_diario.sh              (todos los días 12:00)
#        ./instalar_backup_diario.sh 21 30        (todos los días 21:30)
#        ./instalar_backup_diario.sh --desinstalar
#
# Antes: backup.env completo (DATABASE_URL y BACKUP_DIR apuntando a una carpeta de Google Drive).
# Copia backup.sh y backup.env a ~/FocoBackup (fuera de Documentos, donde macOS no deja entrar a las
# tareas programadas) y los ejecuta con launchd. Si cambiás backup.env, volvé a correr este instalador.
set -euo pipefail
cd "$(dirname "$0")"

LABEL="net.focobr.backup"
DEST="$HOME/FocoBackup"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

if [ "${1:-}" = "--desinstalar" ]; then
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Backup diario desinstalado. Los backups ya hechos no se tocaron."
  echo "Podés borrar $DEST si no lo usás (tiene la clave de la base en backup.env)."
  exit 0
fi

HOUR="${1:-12}"
MINUTE="${2:-0}"
if ! [[ "$HOUR" =~ ^[0-9]+$ && "$MINUTE" =~ ^[0-9]+$ ]] || [ "$HOUR" -gt 23 ] || [ "$MINUTE" -gt 59 ]; then
  echo "Hora inválida. Ejemplo: ./instalar_backup_diario.sh 12 0"
  exit 1
fi

if [ ! -f backup.env ]; then
  echo "Falta backup.env. Copiá backup.env.example como backup.env y completalo."
  exit 1
fi
# shellcheck disable=SC1091
source backup.env
if [ -z "${DATABASE_URL:-}" ] || [ "$DATABASE_URL" = "PEGAR_ACA_LA_CONEXION_DE_NEON" ]; then
  echo "Falta pegar la conexión de Neon en DATABASE_URL (backup.env)."
  exit 1
fi
if [ -z "${BACKUP_DIR:-}" ]; then
  echo "Falta BACKUP_DIR en backup.env: poné la carpeta de Google Drive donde guardar los backups."
  exit 1
fi
mkdir -p "$BACKUP_DIR"

mkdir -p "$DEST"
cp backup.sh "$DEST/backup.sh"
cp backup.env "$DEST/backup.env"
chmod 700 "$DEST" "$DEST/backup.sh"
chmod 600 "$DEST/backup.env"

mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$DEST/backup.sh</string></array>
  <key>WorkingDirectory</key><string>$DEST</string>
  <!-- Al iniciar sesión: recupera el backup del día si la Mac estaba apagada a la hora programada.
       backup.sh no hace nada si el backup de hoy ya está hecho. -->
  <key>RunAtLoad</key><true/>
  <!-- Todos los días. Si la Mac estaba dormida a esa hora, corre al despertarse. -->
  <key>StartCalendarInterval</key><dict>
    <key>Hour</key><integer>$HOUR</integer>
    <key>Minute</key><integer>$MINUTE</integer>
  </dict>
  <key>StandardOutPath</key><string>$DEST/backup.log</string>
  <key>StandardErrorPath</key><string>$DEST/backup.log</string>
</dict>
</plist>
EOF

read -r -p "¿Hacer un backup de prueba ahora, igual que el programado? [S/n] " answer
# Al instalar, la tarea corre una vez (como al iniciar sesión). Para la prueba se olvida el último
# backup, así lo hace aunque ya haya uno de hoy.
[[ "$answer" =~ ^[nN] ]] || rm -f "$DEST/ultimo_backup"
: > "$DEST/backup.log"
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$PLIST"
printf "Backup programado: todos los días %02d:%02d y al iniciar sesión → %s\n" "$HOUR" "$MINUTE" "$BACKUP_DIR"
echo "Registro: $DEST/backup.log"
if [[ ! "$answer" =~ ^[nN] ]]; then
  echo "Corriendo... (si macOS pide permiso para acceder a Google Drive, aceptalo)"
  for _ in $(seq 1 120); do
    sleep 2
    if grep -qE "Listo:|Omitido|Falta|Atención|rror|denied|not permitted" "$DEST/backup.log" 2>/dev/null; then break; fi
  done
  cat "$DEST/backup.log"
fi
