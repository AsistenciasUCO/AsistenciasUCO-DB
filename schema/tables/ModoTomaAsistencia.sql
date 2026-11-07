USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.1): modo de una toma de asistencia (MANUAL | QR). Los SP lo resuelven por las banderas
-- usaCodigoQr (unica) y marcaAusentesAlCerrar (valor por defecto de @marcarAusentes al cerrar), nunca por el codigo.
-- Filas con ids fijos en la semilla 35_catalogos_toma_asistencia.sql.
IF OBJECT_ID('dbo.[ModoTomaAsistencia]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.ModoTomaAsistencia (
        id                     UNIQUEIDENTIFIER NOT NULL,
        codigo                 NVARCHAR(20)     NOT NULL,
        nombre                 NVARCHAR(50)     NOT NULL,
        usaCodigoQr            BIT              NOT NULL,
        marcaAusentesAlCerrar  BIT              NOT NULL,
        CONSTRAINT PK_ModoTomaAsistencia PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_ModoTomaAsistencia_codigo UNIQUE (codigo),
        CONSTRAINT UQ_ModoTomaAsistencia_usaCodigoQr UNIQUE (usaCodigoQr)
    );
END
GO
