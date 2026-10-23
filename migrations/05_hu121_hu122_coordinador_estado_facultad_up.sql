USE [gestionasistenciadb];
GO

SET NOCOUNT ON;

-- HU121/HU122 (CONTRACT congelado 2026-10-22, D1/D2). Idempotente: se puede ejecutar varias veces.
-- Equivale a lo que ya hacen schema/tables/Coordinador.sql y zz_foreign_keys.sql en cada despliegue; existe para
-- aplicarlo de forma aislada y para reportar los coordinadores huerfanos.
IF COL_LENGTH('dbo.Coordinador', 'estado') IS NULL
    ALTER TABLE [dbo].[Coordinador] ADD [estado] bit NOT NULL CONSTRAINT [DF_Coordinador_estado] DEFAULT (1);
GO

IF COL_LENGTH('dbo.Coordinador', 'facultad') IS NULL
    ALTER TABLE [dbo].[Coordinador] ADD [facultad] uniqueidentifier NULL;
GO

EXEC('UPDATE c SET c.facultad = p.facultad
      FROM dbo.Coordinador c
      INNER JOIN dbo.Programa p ON p.coordinador = c.id
      WHERE c.facultad IS NULL');
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Coordinador_Facultad')
    ALTER TABLE [dbo].[Coordinador] ADD CONSTRAINT [FK_Coordinador_Facultad]
    FOREIGN KEY ([facultad]) REFERENCES [dbo].[Facultad] ([id]);
GO

-- Reporte de huerfanos (R3 del PLAN): coordinadores sin programa y sin facultad deducible.
EXEC('SELECT c.id AS idCoordinadorHuerfano, c.usuario AS idUsuario
      FROM dbo.Coordinador c
      WHERE c.facultad IS NULL');
GO
