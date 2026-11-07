USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.1): estado de una toma de asistencia (ABIERTA | CERRADA), resuelto por la bandera estaAbierta
-- (unica). Invariante INV_TOMA_ESTADO_CIERRE: estaAbierta = 1 <=> TomaAsistencia.fechaCierreUtc IS NULL.
IF OBJECT_ID('dbo.[EstadoTomaAsistencia]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.EstadoTomaAsistencia (
        id           UNIQUEIDENTIFIER NOT NULL,
        codigo       NVARCHAR(20)     NOT NULL,
        nombre       NVARCHAR(50)     NOT NULL,
        estaAbierta  BIT              NOT NULL,
        CONSTRAINT PK_EstadoTomaAsistencia PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_EstadoTomaAsistencia_codigo UNIQUE (codigo),
        CONSTRAINT UQ_EstadoTomaAsistencia_estaAbierta UNIQUE (estaAbierta)
    );
END
GO
