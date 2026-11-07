USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.3 (CONTRACT v2 §4.2, [SUPUESTO-D-04]): historial inmutable de cambios de parametros hechos por el administrador
-- (HU168). Lo escribe usp_actualizar_parametro en la misma transaccion que el UPDATE de CatalogoParametro: valor anterior y
-- nuevo, motivo, ejecutor y correlacion. Solo se inserta; no se actualiza ni se borra (el down de la migracion 22 lo archiva).
IF OBJECT_ID('dbo.[CambioParametro]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CambioParametro (
        id                 UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_CambioParametro PRIMARY KEY CLUSTERED,
        parametro          UNIQUEIDENTIFIER NOT NULL,
        valorAnterior      NVARCHAR(4000)   NOT NULL,
        valorNuevo         NVARCHAR(4000)   NOT NULL,
        motivo             NVARCHAR(500)    NOT NULL,
        idUsuarioEjecutor  UNIQUEIDENTIFIER NOT NULL,
        idCorrelacion      UNIQUEIDENTIFIER NOT NULL,
        fechaCambioUtc     DATETIME2(7)     NOT NULL
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.CambioParametro') AND name = 'IX_CambioParametro_Parametro_Fecha')
    CREATE NONCLUSTERED INDEX IX_CambioParametro_Parametro_Fecha ON dbo.CambioParametro (parametro, fechaCambioUtc DESC);
GO
