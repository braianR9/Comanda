#!/bin/bash
# Backup completo de la base (Neon) en un archivo con fecha, en tu computadora.
#
# Uso:   ./backup.sh            (desde Api/dotnet_api/database)
# Config: backup.env en esta carpeta (no se sube a Git). Ver backup.env.example.
#
# Restaurar (siempre en una base o branch NUEVA de Neon, nunca encima de la de producción):
#   pg_restore --no-owner --no-privileges -d "postgresql://...base-nueva..." foco_lunes.dump
#
# Un archivo por día de la semana (foco_lunes.dump … foco_domingo.dump): cada uno pisa el de la
# semana anterior, así siempre hay 7 backups. Ver la fecha real del backup en "Modificado".
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f backup.env ]; then
  echo "Falta backup.env en $(pwd)."
  echo "Copiá backup.env.example como backup.env y pegá la cadena de conexión de Neon."
  exit 1
fi
# shellcheck disable=SC1091
source backup.env

if [ -z "${DATABASE_URL:-}" ] || [ "$DATABASE_URL" = "PEGAR_ACA_LA_CONEXION_DE_NEON" ]; then
  echo "Falta pegar la conexión de Neon en DATABASE_URL (backup.env)."
  exit 1
fi
case "$DATABASE_URL" in
  *-pooler*)
    echo "Atención: la conexión usa el pooler de Neon (-pooler en el host)."
    echo "Para backups usá la conexión directa: en Neon, Connect > desactivá 'Connection pooling'."
    exit 1 ;;
esac

# pg_dump de Homebrew (brew install libpq) no queda en el PATH por defecto.
PG_BIN=""
for dir in "$(dirname "$(command -v pg_dump 2>/dev/null || echo /nonexistent/x)")" \
           /opt/homebrew/opt/libpq/bin /usr/local/opt/libpq/bin; do
  if [ -x "$dir/pg_dump" ]; then PG_BIN="$dir"; break; fi
done
if [ -z "$PG_BIN" ]; then
  echo "Falta pg_dump. Instalalo con:  brew install libpq"
  exit 1
fi

# Programado (launchd): corre a las 12:00 y también al iniciar sesión, para recuperar el del día si
# la Mac estaba apagada. Hace uno solo por día calendario: si hoy ya se hizo, no hace nada.
# A mano (./backup.sh) siempre hace el backup.
mkdir -p "$HOME/FocoBackup"
STAMP="$HOME/FocoBackup/ultimo_backup"
if [ "${XPC_SERVICE_NAME:-}" = "net.focobr.backup" ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$(date +%Y-%m-%d)" ]; then
  echo "$(date '+%Y-%m-%d %H:%M') Omitido: el backup de hoy ya está hecho."
  exit 0
fi
# Un backup por vez (por ejemplo, si coinciden el inicio de sesión y las 12:00). Un candado de más
# de una hora es de un backup que se cortó: se descarta.
LOCK="$HOME/FocoBackup/.backup.lock"
find "$LOCK" -maxdepth 0 -mmin +60 -exec rmdir {} \; 2>/dev/null || true
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "$(date '+%Y-%m-%d %H:%M') Omitido: ya hay un backup en curso."
  exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

BACKUP_DIR="${BACKUP_DIR:-$HOME/Backups/foco}"
# El backup se arma y se verifica primero en esta Mac y después se copia a BACKUP_DIR (por ejemplo
# Google Drive): macOS no deja a las tareas programadas renombrar archivos dentro de Drive.
LOCAL_DIR="$HOME/FocoBackup/backups"
mkdir -p "$BACKUP_DIR" "$LOCAL_DIR"
DAYS=(lunes martes miercoles jueves viernes sabado domingo)
NAME="foco_${DAYS[$(( $(date +%u) - 1 ))]}.dump"
LOCAL="$LOCAL_DIR/$NAME"

echo "$(date '+%Y-%m-%d %H:%M') Haciendo backup ($NAME) ..."
# Formato custom: comprimido y permite restaurar tablas sueltas. Se escribe a un .part y se
# renombra al terminar: si falla, queda intacto el de la semana pasada en lugar de uno a medias.
rm -f "$LOCAL.part"
if ! "$PG_BIN/pg_dump" --format=custom --no-owner --no-privileges --file="$LOCAL.part" "$DATABASE_URL"; then
  rm -f "$LOCAL.part"
  echo "Error: no se pudo hacer el backup. Quedó el de la semana pasada."
  exit 1
fi

# Comprueba que el archivo se pueda leer antes de darlo por bueno.
if ! TABLES=$("$PG_BIN/pg_restore" --list "$LOCAL.part" | grep -c " TABLE DATA "); then
  rm -f "$LOCAL.part"
  echo "Error: el backup no se puede leer. Quedó el de la semana pasada."
  exit 1
fi
mv -f "$LOCAL.part" "$LOCAL"
echo "Backup local: $LOCAL ($(du -h "$LOCAL" | cut -f1) · $TABLES tablas con datos)"

if [ "$BACKUP_DIR" != "$LOCAL_DIR" ]; then
  rm -f "$BACKUP_DIR/$NAME.part" 2>/dev/null || true
  if cp -f "$LOCAL" "$BACKUP_DIR/$NAME"; then
    echo "Copiado a $BACKUP_DIR/$NAME"
  else
    echo "Error: no se pudo copiar a $BACKUP_DIR (quedó el backup local)."
    exit 1
  fi
fi
date +%Y-%m-%d > "$STAMP"
echo "Listo: $(du -h "$LOCAL" | cut -f1) · $TABLES tablas con datos."
