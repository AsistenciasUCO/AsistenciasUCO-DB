USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU090: catalogo de tipos de vinculacion del docente con el programa.
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
