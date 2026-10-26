-- Motivo obligatorio de cada nota de crédito (queda en el historial de comprobantes).
-- Ejecutar como propietario de las tablas después de add_facturacion_afip.sql. Repetible.
BEGIN;
ALTER TABLE comprobantes ADD COLUMN IF NOT EXISTS motivo varchar(500) NOT NULL DEFAULT '';
COMMIT;
