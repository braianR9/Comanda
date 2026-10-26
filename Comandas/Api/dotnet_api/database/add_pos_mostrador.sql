BEGIN;

-- Venta directa (mostrador/kiosco) sin mesa física: reutiliza el mismo
-- flujo de ventas, pagos, comandas y caja que las mesas, contra una mesa
-- virtual marcada como "mostrador" que admite varias ventas simultáneas.

ALTER TABLE sectores ADD COLUMN IF NOT EXISTS es_sistema boolean NOT NULL DEFAULT false;
ALTER TABLE mesas ADD COLUMN IF NOT EXISTS es_mostrador boolean NOT NULL DEFAULT false;

-- Código de barras para pistoleo en el punto de venta.
ALTER TABLE productos ADD COLUMN IF NOT EXISTS codigo_barras varchar(50) NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_productos_empresa_codigo_barras
    ON productos (id_empresa, codigo_barras) WHERE codigo_barras IS NOT NULL;

-- El sector y la mesa "Mostrador" se crean de forma perezosa (on-demand) la
-- primera vez que una sucursal usa la venta directa; no requieren backfill.

COMMIT;
