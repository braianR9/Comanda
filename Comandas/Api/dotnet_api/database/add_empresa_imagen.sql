ALTER TABLE public.empresas
ADD COLUMN IF NOT EXISTS imagen_url text;

GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLE public.empresas
TO foco_api;
