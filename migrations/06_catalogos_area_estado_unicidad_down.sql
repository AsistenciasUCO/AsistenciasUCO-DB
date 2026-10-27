USE [gestionasistenciadb];
GO

SET NOCOUNT ON;

-- Rollback de HU151/HU152/HU154. Idempotente. Antes hay que desplegar la version previa de uv_area
-- (sin codigo ni estaActivaArea) y retirar los SP usp_*_area.
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TipoPrograma_nombre' AND object_id = OBJECT_ID('dbo.TipoPrograma'))
    DROP INDEX [UX_TipoPrograma_nombre] ON [dbo].[TipoPrograma];
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TipoPrograma_codigo' AND object_id = OBJECT_ID('dbo.TipoPrograma'))
    DROP INDEX [UX_TipoPrograma_codigo] ON [dbo].[TipoPrograma];
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Area_nombre' AND object_id = OBJECT_ID('dbo.Area'))
    DROP INDEX [UX_Area_nombre] ON [dbo].[Area];
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Area_codigo' AND object_id = OBJECT_ID('dbo.Area'))
    DROP INDEX [UX_Area_codigo] ON [dbo].[Area];
GO

IF EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_Area_estado')
    ALTER TABLE [dbo].[Area] DROP CONSTRAINT [DF_Area_estado];
GO

IF COL_LENGTH('dbo.Area', 'estado') IS NOT NULL
    ALTER TABLE [dbo].[Area] DROP COLUMN [estado];
GO
