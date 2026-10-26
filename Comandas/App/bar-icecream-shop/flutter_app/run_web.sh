#!/bin/sh
# Ejecuta la app en Chrome con la URL y la API Key de config/local.json.
cd "$(dirname "$0")" && exec flutter run -d chrome --dart-define-from-file=config/local.json "$@"
