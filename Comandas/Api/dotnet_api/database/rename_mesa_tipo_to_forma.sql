BEGIN;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'mesas' AND column_name = 'tipo'
    ) AND NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'mesas' AND column_name = 'forma'
    ) THEN
        ALTER TABLE mesas RENAME COLUMN tipo TO forma;
    END IF;
END $$;

ALTER TABLE mesas DROP CONSTRAINT IF EXISTS mesas_tipo_check;
ALTER TABLE mesas DROP CONSTRAINT IF EXISTS mesas_forma_check;
UPDATE mesas SET forma = 'Circular' WHERE forma = 'Redonda';
UPDATE mesas SET forma = 'Rectangular' WHERE forma = 'Ovalada';
ALTER TABLE mesas ADD CONSTRAINT mesas_forma_check
    CHECK (forma IN ('Circular', 'Cuadrada', 'Rectangular'));

COMMIT;
