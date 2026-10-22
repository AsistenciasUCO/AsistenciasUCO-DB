USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Coordinador]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Coordinador] (
    [id] uniqueidentifier NOT NULL,
    [usuario] uniqueidentifier NOT NULL
);

ALTER TABLE [dbo].[Coordinador] ADD CONSTRAINT [PK_Coordinador] PRIMARY KEY CLUSTERED ([id]);
END
GO

-- HU121/HU122 (D1): estado propio del rol de coordinador. Las filas existentes quedan activas.
IF COL_LENGTH('dbo.Coordinador', 'estado') IS NULL
BEGIN
    ALTER TABLE [dbo].[Coordinador] ADD [estado] bit NOT NULL CONSTRAINT [DF_Coordinador_estado] DEFAULT (1);
END
GO

-- HU121/HU122 (D2): facultad del coordinador, necesaria para el ambito cuando aun no tiene programa.
IF COL_LENGTH('dbo.Coordinador', 'facultad') IS NULL
BEGIN
    ALTER TABLE [dbo].[Coordinador] ADD [facultad] uniqueidentifier NULL;
END
GO

-- Relleno desde la facultad del programa que ya coordina (idempotente). Los coordinadores sin programa quedan
-- con facultad NULL hasta que un decano los edite o se sanee el dato (ver migrations/05_*).
IF COL_LENGTH('dbo.Coordinador', 'facultad') IS NOT NULL AND OBJECT_ID('dbo.Programa', 'U') IS NOT NULL
BEGIN
    EXEC('UPDATE c SET c.facultad = p.facultad
          FROM dbo.Coordinador c
          INNER JOIN dbo.Programa p ON p.coordinador = c.id
          WHERE c.facultad IS NULL');
END
GO
