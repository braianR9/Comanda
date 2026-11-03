// Guarda un archivo generado por la API: en la web lo descarga el navegador;
// en escritorio/móvil se elige dónde guardarlo.
export 'file_download_native.dart'
    if (dart.library.js_interop) 'file_download_web.dart';
