-- Ejecutar antes de desplegar la API con importación de productos. No carga productos.
BEGIN;
ALTER TABLE productos ADD COLUMN IF NOT EXISTS codigo_importacion varchar(100);
CREATE UNIQUE INDEX IF NOT EXISTS ux_productos_empresa_codigo_importacion
    ON productos(id_empresa, codigo_importacion);
COMMIT;
