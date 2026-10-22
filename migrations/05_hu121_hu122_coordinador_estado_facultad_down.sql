USE [gestionasistenciadb];
GO

SET NOCOUNT ON;

-- Rollback de HU121/HU122 (D1/D2). Idempotente. Quita FK, DEFAULT y las dos columnas nuevas.
-- Antes de ejecutarlo hay que desplegar las versiones previas de uv_coordinador, uv_coordinador_identidad y
-- uv_usuario_perfil, que dependen de estas columnas.
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Coordinador_Facultad')
    ALTER TABLE [dbo].[Coordinador] DROP CONSTRAINT [FK_Coordinador_Facultad];
GO

IF EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_Coordinador_estado')
    ALTER TABLE [dbo].[Coordinador] DROP CONSTRAINT [DF_Coordinador_estado];
GO

IF COL_LENGTH('dbo.Coordinador', 'estado') IS NOT NULL
    ALTER TABLE [dbo].[Coordinador] DROP COLUMN [estado];
GO

IF COL_LENGTH('dbo.Coordinador', 'facultad') IS NOT NULL
    ALTER TABLE [dbo].[Coordinador] DROP COLUMN [facultad];
GO
