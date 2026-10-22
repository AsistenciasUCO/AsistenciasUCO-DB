USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Modalidad]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Modalidad] (
    [id] uniqueidentifier NOT NULL,
    [codigo] nvarchar(3) NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [estado] bit NOT NULL
);

ALTER TABLE [dbo].[Modalidad] ADD CONSTRAINT [PK_Modalidad] PRIMARY KEY CLUSTERED ([id]);
ALTER TABLE [dbo].[Modalidad] ADD CONSTRAINT [UQ_Modalidad_codigo] UNIQUE ([codigo]);
END
GO
