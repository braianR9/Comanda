-- Cierre de caja: número de cierre por sucursal, efectivo contado al cerrar y
-- monto que se deja para la próxima apertura (el resto se retira). Ejecutar como propietario.
BEGIN;
ALTER TABLE cajas ADD COLUMN IF NOT EXISTS numero_cierre integer NULL;
ALTER TABLE cajas ADD COLUMN IF NOT EXISTS monto_contado numeric(18,2) NULL CHECK (monto_contado >= 0);
ALTER TABLE cajas ADD COLUMN IF NOT EXISTS monto_proxima_apertura numeric(18,2) NULL CHECK (monto_proxima_apertura >= 0);

-- Los cierres anteriores se numeran en orden de cierre.
UPDATE cajas c SET numero_cierre = n.numero
FROM (SELECT id_caja, row_number() OVER (PARTITION BY id_empresa, id_sucursal ORDER BY fecha_cierre, id_caja) AS numero
      FROM cajas WHERE estado = 'Cerrada') n
WHERE c.id_caja = n.id_caja AND c.numero_cierre IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_cajas_numero_cierre
    ON cajas(id_empresa, id_sucursal, numero_cierre) WHERE numero_cierre IS NOT NULL;
COMMIT;
