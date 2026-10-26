-- Impresión y reimpresión de comprobantes electrónicos (facturas y notas de crédito),
-- con el usuario que la pidió. Ejecutar como propietario de las tablas después de
-- add_nota_credito_motivo.sql. Repetible.
BEGIN;
ALTER TABLE trabajos_impresion ADD COLUMN IF NOT EXISTS id_comprobante integer REFERENCES comprobantes(id_comprobante);
ALTER TABLE trabajos_impresion ADD COLUMN IF NOT EXISTS id_usuario integer REFERENCES usuarios(id_usuario);
ALTER TABLE trabajos_impresion ADD COLUMN IF NOT EXISTS reimpresion boolean NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS ix_trabajos_impresion_comprobante ON trabajos_impresion(id_comprobante) WHERE id_comprobante IS NOT NULL;
COMMIT;
