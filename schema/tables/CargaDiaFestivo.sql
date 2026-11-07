USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.1 (CONTRACT §2.2): bitacora de cada carga anual de festivos (fuente, fecha, conteos y diferencias con el
-- calculo local, que calcula el backend). usuarioEjecutor NULL = job automatico.
IF OBJECT_ID('dbo.[CargaDiaFestivo]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CargaDiaFestivo (
        id                        UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_CargaDiaFestivo_id DEFAULT NEWID(),
        anio                      SMALLINT         NOT NULL,
        fuente                    NVARCHAR(40)     NOT NULL,
        totalFestivos             INT              NOT NULL,
        festivosInsertados        INT              NOT NULL,
        festivosActualizados      INT              NOT NULL,
        festivosDesactivados      INT              NOT NULL,
        diferenciasCalculoLocal   INT              NOT NULL,
        usuarioEjecutor           UNIQUEIDENTIFIER NULL,
        fechaCargaUtc             DATETIME2(0)     NOT NULL,
        idCorrelacion             UNIQUEIDENTIFIER NOT NULL,
        CONSTRAINT PK_CargaDiaFestivo PRIMARY KEY CLUSTERED (id),
        CONSTRAINT CK_CargaDiaFestivo_conteos CHECK (totalFestivos >= 0 AND festivosInsertados >= 0 AND festivosActualizados >= 0
                                                    AND festivosDesactivados >= 0 AND diferenciasCalculoLocal >= 0)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.CargaDiaFestivo') AND name = 'IX_CargaDiaFestivo_anio_fecha')
    CREATE NONCLUSTERED INDEX IX_CargaDiaFestivo_anio_fecha ON dbo.CargaDiaFestivo (anio, fechaCargaUtc DESC);
GO
