USE [gestionasistenciadb];
GO

SET NOCOUNT ON;

-- HU062/HU091 (D1, D2, D7): migracion idempotente para bases existentes. Las vistas y SP nuevos se aplican con
-- deploy_schema.ps1; esta migracion cubre DDL, semilla de catalogo, backfill de vinculos y retiro del SP autonomo.
-- DOWN (manual, sin datos previos que perder):
--   DROP TABLE dbo.DocentePrograma; DROP TABLE dbo.TipoVinculacion;
--   (el SP retirado se restaura desde git: schema/stored-procedures/usp_registrar_docente_en_grupo_autonomo.sql)

IF OBJECT_ID('dbo.[TipoVinculacion]', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[TipoVinculacion] (
        [id] uniqueidentifier NOT NULL,
        [codigo] nvarchar(3) NOT NULL,
        [nombre] nvarchar(50) NOT NULL,
        [estado] bit NOT NULL
    );
    ALTER TABLE [dbo].[TipoVinculacion] ADD CONSTRAINT [PK_TipoVinculacion] PRIMARY KEY CLUSTERED ([id]);
    ALTER TABLE [dbo].[TipoVinculacion] ADD CONSTRAINT [UQ_TipoVinculacion_codigo] UNIQUE ([codigo]);
END
GO

IF OBJECT_ID('dbo.[DocentePrograma]', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[DocentePrograma] (
        [id] uniqueidentifier NOT NULL,
        [docente] uniqueidentifier NOT NULL,
        [programa] uniqueidentifier NOT NULL,
        [tipoVinculacion] uniqueidentifier NOT NULL,
        [estado] bit NOT NULL,
        [fechaVinculacionUtc] datetime2(0) NOT NULL
    );
    ALTER TABLE [dbo].[DocentePrograma] ADD CONSTRAINT [PK_DocentePrograma] PRIMARY KEY CLUSTERED ([id]);
    ALTER TABLE [dbo].[DocentePrograma] ADD CONSTRAINT [UQ_DocentePrograma_docente_programa] UNIQUE ([docente], [programa]);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_DocentePrograma_Docente')
    ALTER TABLE [dbo].[DocentePrograma] ADD CONSTRAINT [FK_DocentePrograma_Docente] FOREIGN KEY ([docente]) REFERENCES [dbo].[Docente] ([id]);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_DocentePrograma_Programa')
    ALTER TABLE [dbo].[DocentePrograma] ADD CONSTRAINT [FK_DocentePrograma_Programa] FOREIGN KEY ([programa]) REFERENCES [dbo].[Programa] ([id]);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_DocentePrograma_TipoVinculacion')
    ALTER TABLE [dbo].[DocentePrograma] ADD CONSTRAINT [FK_DocentePrograma_TipoVinculacion] FOREIGN KEY ([tipoVinculacion]) REFERENCES [dbo].[TipoVinculacion] ([id]);
GO

-- Catalogo, parametros y backfill (R2): idempotentes, definidos en schema/seed/16_tipo_vinculacion.sql.
PRINT 'Migracion 05: ejecute schema/seed/16_tipo_vinculacion.sql y 17_mensaje_docente_programa.sql tras deploy_schema.ps1 (backfill R2 depende de uv_docente).';
GO

-- D7: retiro del SP autonomo sin RBAC (sin consumidores).
DROP PROCEDURE IF EXISTS dbo.usp_registrar_docente_en_grupo_autonomo;
GO
