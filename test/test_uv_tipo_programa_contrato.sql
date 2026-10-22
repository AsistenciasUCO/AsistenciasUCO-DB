USE [gestionasistenciadb];
GO
SET NOCOUNT ON;

PRINT 'TEST START: test_uv_tipo_programa_contrato (HU023/HU154)';

-- DB-19: la vista expone codigo y conserva el seed canonico
IF COL_LENGTH('dbo.uv_tipo_programa', 'codigo') IS NULL
    THROW 52670, 'TEST FAILED DB-19: uv_tipo_programa no expone codigo.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.uv_tipo_programa WHERE codigo = N'PRE')
   OR NOT EXISTS (SELECT 1 FROM dbo.uv_tipo_programa WHERE codigo = N'POS')
    THROW 52671, 'TEST FAILED DB-19: faltan los tipos PRE/POS del seed.', 1;

PRINT 'TEST PASS: test_uv_tipo_programa_contrato';
GO
