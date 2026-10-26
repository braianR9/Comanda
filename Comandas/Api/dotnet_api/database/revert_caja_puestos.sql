-- Volver a una caja abierta por sucursal, conservando los datos existentes.
-- Ejecutar como propietario de las tablas.
BEGIN;
LOCK TABLE cajas IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM cajas WHERE estado = 'Abierta' GROUP BY id_sucursal HAVING count(*) > 1) THEN
        RAISE EXCEPTION 'Hay sucursales con varias cajas abiertas. Cerrá los turnos adicionales antes de revertir.';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cajas' AND column_name = 'id_puesto') THEN
        ALTER TABLE cajas ALTER COLUMN id_puesto DROP NOT NULL;
    END IF;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS ux_cajas_sucursal_abierta
    ON cajas(id_sucursal) WHERE estado = 'Abierta';
-- Las columnas y configuraciones previas se conservan como datos históricos.
COMMIT;
