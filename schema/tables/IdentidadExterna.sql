USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SEC-BASELINE-017: vinculo persistente entre una identidad OIDC externa (emisor + sujeto) y Usuario.id.
-- El correo institucional verificado solo sirve para la vinculacion inicial; despues el vinculo se resuelve
-- por (emisor, sujeto) y un cambio de correo en el IdP no reasigna la cuenta. No almacena tokens ni secretos.
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

-- Una identidad externa ocupa una sola cuenta, vigente o revocada: reutilizarla exige una decision explicita.
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_IdentidadExterna_emisor_sujeto')
    ALTER TABLE [dbo].[IdentidadExterna] ADD CONSTRAINT [UQ_IdentidadExterna_emisor_sujeto] UNIQUE ([emisor], [sujeto]);
GO

-- Una cuenta tiene como maximo una identidad vigente por emisor.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_IdentidadExterna_usuario_emisor_vigente' AND object_id = OBJECT_ID('dbo.IdentidadExterna'))
    CREATE UNIQUE NONCLUSTERED INDEX [UX_IdentidadExterna_usuario_emisor_vigente]
        ON [dbo].[IdentidadExterna] ([usuario], [emisor]) WHERE [estado] = 1;
GO
