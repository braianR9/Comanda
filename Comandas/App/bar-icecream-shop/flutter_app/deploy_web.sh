#!/bin/bash
# Publica app.focobr.net: la landing en "/" y el sistema en "/ingresar" (y "/sistemas").
# Uso: ./deploy_web.sh   (desde flutter_app, con config/prod.json)
set -euo pipefail
cd "$(dirname "$0")"
flutter build web --release --dart-define-from-file=config/prod.json
# El index de Flutter pasa a /ingresar y /sistemas; en "/" queda la landing.
cp build/web/index.html build/web/ingresar.html
cp build/web/index.html build/web/sistemas.html
cp ../../../Landing/public/index.html build/web/index.html
npx wrangler deploy
