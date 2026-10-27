USE [gestionasistenciadb];
GO
SET NOCOUNT ON;

PRINT 'TEST START: test_uv_area_contrato (HU151/HU152)';

-- DB-19: la vista expone codigo y estado
IF COL_LENGTH('dbo.uv_area', 'codigo') IS NULL
    THROW 52770, 'TEST FAILED DB-19: uv_area no expone codigo.', 1;
IF COL_LENGTH('dbo.uv_area', 'estaActivaArea') IS NULL
    THROW 52771, 'TEST FAILED DB-19: uv_area no expone estaActivaArea.', 1;
IF EXISTS (SELECT 1 FROM dbo.uv_area WHERE estaActivaArea IS NULL)
    THROW 52772, 'TEST FAILED DB-20: hay areas sin estado tras la migracion.', 1;

-- DB-21: indices unicos
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Area_codigo' AND object_id = OBJECT_ID('dbo.Area') AND is_unique = 1)
    THROW 52773, 'TEST FAILED DB-21: falta UX_Area_codigo.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Area_nombre' AND object_id = OBJECT_ID('dbo.Area') AND is_unique = 1)
    THROW 52774, 'TEST FAILED DB-21: falta UX_Area_nombre.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TipoPrograma_codigo' AND object_id = OBJECT_ID('dbo.TipoPrograma') AND is_unique = 1)
    THROW 52775, 'TEST FAILED DB-21: falta UX_TipoPrograma_codigo.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TipoPrograma_nombre' AND object_id = OBJECT_ID('dbo.TipoPrograma') AND is_unique = 1)
    THROW 52776, 'TEST FAILED DB-21: falta UX_TipoPrograma_nombre.', 1;

PRINT 'TEST PASS: test_uv_area_contrato';
GO
