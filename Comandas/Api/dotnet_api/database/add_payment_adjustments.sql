-- Ejecutar después de add_sales_module.sql y add_cards_catalog.sql, antes de iniciar la API.
BEGIN;
ALTER TABLE venta_pagos ALTER COLUMN id_tipo_cobro DROP NOT NULL;
ALTER TABLE venta_pagos ALTER COLUMN tipo_cobro_nombre TYPE varchar(150);
ALTER TABLE venta_pagos ADD COLUMN IF NOT EXISTS id_tarjeta integer REFERENCES tarjetas(id_tarjeta) ON DELETE RESTRICT;
ALTER TABLE venta_pagos ADD COLUMN IF NOT EXISTS importe_base numeric(18,2);
ALTER TABLE venta_pagos ADD COLUMN IF NOT EXISTS tipo_ajuste varchar(20) NOT NULL DEFAULT 'SinAjuste';
ALTER TABLE venta_pagos ADD COLUMN IF NOT EXISTS porcentaje numeric(5,2) NOT NULL DEFAULT 0;
ALTER TABLE venta_pagos ADD COLUMN IF NOT EXISTS importe_ajuste numeric(18,2) NOT NULL DEFAULT 0;
UPDATE venta_pagos SET importe_base = importe WHERE importe_base IS NULL;
ALTER TABLE venta_pagos DROP CONSTRAINT IF EXISTS venta_pagos_importe_check;
ALTER TABLE venta_pagos ADD CONSTRAINT venta_pagos_importe_check CHECK (importe >= 0);
CREATE INDEX IF NOT EXISTS ix_venta_pagos_tarjeta ON venta_pagos(id_tarjeta);
COMMIT;
