USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Decano]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Decano] (
    [id] uniqueidentifier NOT NULL,
    [usuario] uniqueidentifier NOT NULL
);

ALTER TABLE [dbo].[Decano] ADD CONSTRAINT [PK_Decano] PRIMARY KEY CLUSTERED ([id]);
END
GO

-- CULM-001 A.2-8 (A2-C5, F-ADM-002): estado propio del rol de decano, mismo patron que Coordinador (HU121/HU122).
-- Las filas existentes quedan activas.
IF COL_LENGTH('dbo.Decano', 'estado') IS NULL
BEGIN
    ALTER TABLE [dbo].[Decano] ADD [estado] bit NOT NULL CONSTRAINT [DF_Decano_estado] DEFAULT (1);
END
GO
