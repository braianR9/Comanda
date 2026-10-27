-- Prueba de impresora como trabajo de la cola, para que la imprima el agente local
-- cuando la API corre en la nube. Ejecutar como propietario de las tablas.
BEGIN;

ALTER TABLE trabajos_impresion DROP CONSTRAINT IF EXISTS ck_trabajos_impresion_referencia;
ALTER TABLE trabajos_impresion ADD CONSTRAINT ck_trabajos_impresion_referencia
    CHECK (id_venta IS NOT NULL OR id_caja IS NOT NULL
        OR (tipo = 'Prueba' AND id_impresora_configuracion IS NOT NULL));

ALTER TABLE trabajos_impresion DROP CONSTRAINT IF EXISTS trabajos_impresion_tipo_check;
ALTER TABLE trabajos_impresion ADD CONSTRAINT trabajos_impresion_tipo_check
    CHECK (tipo IN ('Comanda', 'TicketVenta', 'CierreCaja', 'Prueba'));

COMMIT;
