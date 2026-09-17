BEGIN;

ALTER TABLE subrubros ADD COLUMN IF NOT EXISTS descripcion varchar(2000) NULL;
ALTER TABLE subrubros ADD COLUMN IF NOT EXISTS tipo_observacion varchar(50) NOT NULL DEFAULT 'SinObservaciones';
ALTER TABLE subrubros ADD COLUMN IF NOT EXISTS imagen_url text NULL;
ALTER TABLE subrubros ADD COLUMN IF NOT EXISTS aplicar_productos boolean NOT NULL DEFAULT true;
ALTER TABLE subrubros ADD COLUMN IF NOT EXISTS aplicar_ingredientes boolean NOT NULL DEFAULT false;
ALTER TABLE subrubros ADD COLUMN IF NOT EXISTS aplicar_delivery boolean NOT NULL DEFAULT false;
ALTER TABLE subrubros ADD COLUMN IF NOT EXISTS aplicar_salon boolean NOT NULL DEFAULT false;
ALTER TABLE subrubros ADD COLUMN IF NOT EXISTS mostrar_carta_digital boolean NOT NULL DEFAULT false;

COMMIT;
