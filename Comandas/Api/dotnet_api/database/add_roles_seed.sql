BEGIN;
INSERT INTO roles(nombre)
SELECT nombre FROM (VALUES ('ADMIN'), ('CAJA'), ('EMPLEADO')) AS seed(nombre)
WHERE NOT EXISTS (SELECT 1 FROM roles r WHERE r.nombre = seed.nombre
 OR (seed.nombre = 'CAJA' AND r.nombre = 'ENCARGADO'));
COMMIT;
