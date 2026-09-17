BEGIN;
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS id_sector_asignado integer NULL
  REFERENCES sectores(id_sector) ON DELETE SET NULL;
CREATE TABLE IF NOT EXISTS usuario_mesas_excluidas(
  id_usuario integer NOT NULL REFERENCES usuarios(id_usuario) ON DELETE CASCADE,
  id_mesa integer NOT NULL REFERENCES mesas(id_mesa) ON DELETE CASCADE,
  PRIMARY KEY (id_usuario, id_mesa)
);
COMMIT;
