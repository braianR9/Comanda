BEGIN;
INSERT INTO roles(nombre)
SELECT nombre FROM (VALUES ('ADMIN'), ('ENCARGADO'), ('EMPLEADO')) AS seed(nombre)
WHERE NOT EXISTS (SELECT 1 FROM roles r WHERE r.nombre = seed.nombre);
COMMIT;
