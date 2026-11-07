USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.2, DEC-011, DEC-013): toma de asistencia de una sesion. Una sesion tiene de 0 a
-- TOMA_ASISTENCIA/MAXIMO_TOMAS_POR_SESION tomas numeradas 1..n; a lo sumo una ABIERTA (indice filtrado por
-- fechaCierreUtc IS NULL, sin literal de estado). esImplicita = 1: toma creada por el lote legado o por el backfill
-- (nace CERRADA). docenteApertura NULL solo en el backfill.
IF OBJECT_ID('dbo.[TomaAsistencia]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.TomaAsistencia (
        id                     UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_TomaAsistencia_id DEFAULT NEWID(),
        sesion                 UNIQUEIDENTIFIER NOT NULL,
        numero                 SMALLINT         NOT NULL,
        modo                   UNIQUEIDENTIFIER NOT NULL,
        estado                 UNIQUEIDENTIFIER NOT NULL,
        esImplicita            BIT              NOT NULL CONSTRAINT DF_TomaAsistencia_esImplicita DEFAULT 0,
        docenteApertura        UNIQUEIDENTIFIER NULL,
        fechaAperturaUtc       DATETIME2(0)     NOT NULL,
        fechaCierreUtc         DATETIME2(0)     NULL,
        totalAusentesMarcados  INT              NOT NULL CONSTRAINT DF_TomaAsistencia_ausentes DEFAULT 0,
        idCorrelacionApertura  UNIQUEIDENTIFIER NOT NULL,
        idCorrelacionCierre    UNIQUEIDENTIFIER NULL,
        CONSTRAINT PK_TomaAsistencia PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_TomaAsistencia_Sesion_Numero UNIQUE (sesion, numero),
        CONSTRAINT CK_TomaAsistencia_numero CHECK (numero >= 1),
        CONSTRAINT CK_TomaAsistencia_cierre CHECK (fechaCierreUtc IS NULL OR fechaCierreUtc >= fechaAperturaUtc),
        CONSTRAINT CK_TomaAsistencia_ausentes CHECK (totalAusentesMarcados >= 0)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TomaAsistencia') AND name = 'UX_TomaAsistencia_Sesion_Abierta')
    CREATE UNIQUE NONCLUSTERED INDEX UX_TomaAsistencia_Sesion_Abierta ON dbo.TomaAsistencia (sesion) WHERE fechaCierreUtc IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TomaAsistencia') AND name = 'IX_TomaAsistencia_abiertas')
    CREATE NONCLUSTERED INDEX IX_TomaAsistencia_abiertas ON dbo.TomaAsistencia (fechaAperturaUtc) INCLUDE (sesion, modo) WHERE fechaCierreUtc IS NULL;
GO
