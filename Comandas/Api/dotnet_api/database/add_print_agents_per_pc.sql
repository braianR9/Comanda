-- Un agente de impresión por computadora: la sucursal puede tener varios y cada impresora
-- indica qué computadora la imprime. Requiere add_print_agents.sql. Ejecutar como propietario.
BEGIN;
ALTER TABLE agentes_impresion DROP CONSTRAINT IF EXISTS uq_agentes_impresion_sucursal;
ALTER TABLE agentes_impresion ADD COLUMN IF NOT EXISTS nombre varchar(100) NOT NULL DEFAULT 'Computadora';
CREATE INDEX IF NOT EXISTS ix_agentes_impresion_sucursal ON agentes_impresion(id_empresa, id_sucursal);
-- Sin computadora asignada, la imprime la primera computadora agregada en la sucursal.
ALTER TABLE impresoras ADD COLUMN IF NOT EXISTS id_agente_impresion integer NULL
    REFERENCES agentes_impresion(id_agente_impresion) ON DELETE SET NULL;
COMMIT;
