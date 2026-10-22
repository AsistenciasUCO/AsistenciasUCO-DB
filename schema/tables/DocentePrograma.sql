USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU062/HU091/HU093: adscripcion (vinculo) del docente a un programa, con tipo de vinculacion y estado propio.
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
