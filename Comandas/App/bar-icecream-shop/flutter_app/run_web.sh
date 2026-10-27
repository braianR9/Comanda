#!/bin/sh
# Ejecuta la app en Chrome (puerto 3000, el permitido por CORS en la API) con config/local.json.
cd "$(dirname "$0")" && exec flutter run -d chrome --web-port 3000 --dart-define-from-file=config/local.json "$@"
