USE [gestionasistenciadb];
GO

SET NOCOUNT ON;

-- HU151/HU152/HU154 (CONTRACT congelado 2026-10-22, D2/D4). Idempotente.
-- Aborta si existen duplicados previos de codigo o nombre, para que se saneen a mano antes de crear los indices.
IF EXISTS (SELECT codigo FROM dbo.Area GROUP BY codigo HAVING COUNT(*) > 1)
   OR EXISTS (SELECT nombre FROM dbo.Area GROUP BY nombre HAVING COUNT(*) > 1)
   OR EXISTS (SELECT codigo FROM dbo.TipoPrograma GROUP BY codigo HAVING COUNT(*) > 1)
   OR EXISTS (SELECT nombre FROM dbo.TipoPrograma GROUP BY nombre HAVING COUNT(*) > 1)
    THROW 52800, 'MIGRACION ABORTADA: hay codigos o nombres duplicados en Area o TipoPrograma. Sanear antes de continuar.', 1;
GO

IF COL_LENGTH('dbo.Area', 'estado') IS NULL
    ALTER TABLE [dbo].[Area] ADD [estado] bit NOT NULL CONSTRAINT [DF_Area_estado] DEFAULT (1);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Area_codigo' AND object_id = OBJECT_ID('dbo.Area'))
    CREATE UNIQUE INDEX [UX_Area_codigo] ON [dbo].[Area] ([codigo]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Area_nombre' AND object_id = OBJECT_ID('dbo.Area'))
    CREATE UNIQUE INDEX [UX_Area_nombre] ON [dbo].[Area] ([nombre]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TipoPrograma_codigo' AND object_id = OBJECT_ID('dbo.TipoPrograma'))
    CREATE UNIQUE INDEX [UX_TipoPrograma_codigo] ON [dbo].[TipoPrograma] ([codigo]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TipoPrograma_nombre' AND object_id = OBJECT_ID('dbo.TipoPrograma'))
    CREATE UNIQUE INDEX [UX_TipoPrograma_nombre] ON [dbo].[TipoPrograma] ([nombre]);
GO
