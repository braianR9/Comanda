BEGIN;

ALTER TABLE trabajos_impresion ALTER COLUMN id_venta DROP NOT NULL;
ALTER TABLE trabajos_impresion ADD COLUMN IF NOT EXISTS id_caja integer REFERENCES cajas(id_caja) ON DELETE CASCADE;

ALTER TABLE trabajos_impresion DROP CONSTRAINT IF EXISTS ck_trabajos_impresion_referencia;
ALTER TABLE trabajos_impresion ADD CONSTRAINT ck_trabajos_impresion_referencia
    CHECK (id_venta IS NOT NULL OR id_caja IS NOT NULL);

ALTER TABLE trabajos_impresion DROP CONSTRAINT IF EXISTS trabajos_impresion_tipo_check;
ALTER TABLE trabajos_impresion ADD CONSTRAINT trabajos_impresion_tipo_check
    CHECK (tipo IN ('Comanda', 'TicketVenta', 'CierreCaja'));

CREATE INDEX IF NOT EXISTS ix_trabajos_impresion_caja
    ON trabajos_impresion(id_caja);

COMMIT;
