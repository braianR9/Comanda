BEGIN;

CREATE UNIQUE INDEX IF NOT EXISTS ux_rubros_empresa_nombre_ci
    ON rubros (id_empresa, lower(nombre));

CREATE UNIQUE INDEX IF NOT EXISTS ux_subrubros_rubro_nombre_ci
    ON subrubros (id_rubro, lower(nombre));

COMMIT;
