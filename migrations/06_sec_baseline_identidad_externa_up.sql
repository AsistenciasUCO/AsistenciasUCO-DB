USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

SET NOCOUNT ON;

-- SEC-BASELINE-017. Idempotente: se puede ejecutar varias veces. Aditiva: no modifica ni elimina objetos existentes.
-- Equivale a schema/tables/IdentidadExterna.sql + FK de zz_foreign_keys.sql; existe para aplicarla de forma aislada
-- sobre una base ya desplegada. La vista y los procedimientos (uv_identidad_externa, usp_vincular_identidad_externa,
-- usp_revocar_identidad_externa) y los GRANT se despliegan con deploy_schema.ps1.
IF OBJECT_ID('dbo.[IdentidadExterna]', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[IdentidadExterna] (
        [id] uniqueidentifier NOT NULL CONSTRAINT [DF_IdentidadExterna_id] DEFAULT (NEWID()),
        [usuario] uniqueidentifier NOT NULL,
        [emisor] nvarchar(400) NOT NULL,
        [sujeto] nvarchar(256) NOT NULL,
        [correoVinculacion] nvarchar(100) NOT NULL,
        [estado] bit NOT NULL CONSTRAINT [DF_IdentidadExterna_estado] DEFAULT (1),
        [fechaVinculacion] datetime2(3) NOT NULL CONSTRAINT [DF_IdentidadExterna_fechaVinculacion] DEFAULT (SYSUTCDATETIME()),
        [fechaRevocacion] datetime2(3) NULL,
        [idCorrelacion] uniqueidentifier NOT NULL
    );
    ALTER TABLE [dbo].[IdentidadExterna] ADD CONSTRAINT [PK_IdentidadExterna] PRIMARY KEY CLUSTERED ([id]);
END
GO

-- Restricciones e indices como pasos independientes: si una ejecucion previa quedo a medias, esta la completa.
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_IdentidadExterna_emisor_sujeto')
    ALTER TABLE [dbo].[IdentidadExterna] ADD CONSTRAINT [UQ_IdentidadExterna_emisor_sujeto] UNIQUE ([emisor], [sujeto]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_IdentidadExterna_usuario_emisor_vigente' AND object_id = OBJECT_ID('dbo.IdentidadExterna'))
    CREATE UNIQUE NONCLUSTERED INDEX [UX_IdentidadExterna_usuario_emisor_vigente]
        ON [dbo].[IdentidadExterna] ([usuario], [emisor]) WHERE [estado] = 1;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_IdentidadExterna_Usuario')
    ALTER TABLE [dbo].[IdentidadExterna] ADD CONSTRAINT [FK_IdentidadExterna_Usuario]
    FOREIGN KEY ([usuario]) REFERENCES [dbo].[Usuario] ([id]);
GO
