USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Jornada]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Jornada] (
    [id] uniqueidentifier NOT NULL,
    [codigo] nvarchar(3) NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [estado] bit NOT NULL
);

ALTER TABLE [dbo].[Jornada] ADD CONSTRAINT [PK_Jornada] PRIMARY KEY CLUSTERED ([id]);
ALTER TABLE [dbo].[Jornada] ADD CONSTRAINT [UQ_Jornada_codigo] UNIQUE ([codigo]);
END
GO
