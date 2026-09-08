BEGIN;

ALTER TABLE mesas ADD COLUMN IF NOT EXISTS posicion_x numeric(8,6) NOT NULL DEFAULT 0;
ALTER TABLE mesas ADD COLUMN IF NOT EXISTS posicion_y numeric(8,6) NOT NULL DEFAULT 0;

ALTER TABLE mesas DROP CONSTRAINT IF EXISTS mesas_posicion_x_check;
ALTER TABLE mesas DROP CONSTRAINT IF EXISTS mesas_posicion_y_check;
ALTER TABLE mesas ADD CONSTRAINT mesas_posicion_x_check CHECK (posicion_x >= 0 AND posicion_x <= 1);
ALTER TABLE mesas ADD CONSTRAINT mesas_posicion_y_check CHECK (posicion_y >= 0 AND posicion_y <= 1);

COMMIT;
