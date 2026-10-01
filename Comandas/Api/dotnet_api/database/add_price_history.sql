BEGIN;
CREATE TABLE IF NOT EXISTS precio_historial (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lote uuid NOT NULL,
    id_empresa integer NOT NULL,
    id_lista_precio integer NOT NULL,
    lista_nombre text NOT NULL,
    id_producto integer NOT NULL,
    producto_nombre text NOT NULL,
    precio_anterior numeric(18,2),
    precio_nuevo numeric(18,2),
    fecha timestamptz NOT NULL DEFAULT clock_timestamp(),
    usuario text NOT NULL,
    motivo text NOT NULL,
    revertido_por uuid
);
CREATE INDEX IF NOT EXISTS ix_precio_historial_empresa ON precio_historial(id_empresa, id DESC);
CREATE INDEX IF NOT EXISTS ix_precio_historial_celda ON precio_historial(id_lista_precio, id_producto, id DESC);
CREATE INDEX IF NOT EXISTS ix_precio_historial_lote ON precio_historial(lote);
CREATE OR REPLACE FUNCTION registrar_precio_historial() RETURNS trigger AS $$
DECLARE
    lista integer;
    producto integer;
    anterior numeric(18,2);
    nuevo numeric(18,2);
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.precio IS NOT DISTINCT FROM NEW.precio THEN RETURN NEW; END IF;
    lista := COALESCE(NEW.id_lista_precio, OLD.id_lista_precio);
    producto := COALESCE(NEW.id_producto, OLD.id_producto);
    IF TG_OP <> 'INSERT' THEN anterior := OLD.precio; END IF;
    IF TG_OP <> 'DELETE' THEN nuevo := NEW.precio; END IF;
    INSERT INTO precio_historial(lote, id_empresa, id_lista_precio, lista_nombre,
        id_producto, producto_nombre, precio_anterior, precio_nuevo, usuario, motivo)
    SELECT COALESCE(NULLIF(current_setting('app.precio_lote', true), '')::uuid, gen_random_uuid()),
        l.id_empresa, lista, l.nombre, producto, p.nombre, anterior, nuevo,
        COALESCE(NULLIF(current_setting('app.precio_usuario', true), ''), 'Sistema / edición de producto'),
        COALESCE(NULLIF(current_setting('app.precio_motivo', true), ''), 'Edición de producto')
    FROM listas_precios l JOIN productos p ON p.id_producto = producto WHERE l.id_lista_precio = lista;
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_precio_historial ON producto_precios;
CREATE TRIGGER trg_precio_historial AFTER INSERT OR UPDATE OR DELETE ON producto_precios
FOR EACH ROW EXECUTE FUNCTION registrar_precio_historial();
-- Permisos para la cuenta de la API local.
GRANT SELECT, INSERT ON precio_historial TO foco_api;
GRANT UPDATE (revertido_por) ON precio_historial TO foco_api;
GRANT USAGE, SELECT ON SEQUENCE precio_historial_id_seq TO foco_api;
COMMIT;
