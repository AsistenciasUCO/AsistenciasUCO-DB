USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.1 (CONTRACT §2.1): catalogo del tipo de cancelacion de una sesion. Los SP distinguen el tipo por la
-- bandera esAutomatica (1 = la crea el sistema por un dia festivo; 0 = la decide el docente), nunca por el codigo.
-- Exactamente un tipo por bandera (UQ_TipoCancelacionSesion_esAutomatica). Filas en la semilla 34 (ids fijos).
IF OBJECT_ID('dbo.[TipoCancelacionSesion]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.TipoCancelacionSesion (
        id            UNIQUEIDENTIFIER NOT NULL,
        codigo        NVARCHAR(20)     NOT NULL,
        nombre        NVARCHAR(50)     NOT NULL,
        esAutomatica  BIT              NOT NULL,
        CONSTRAINT PK_TipoCancelacionSesion PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_TipoCancelacionSesion_codigo UNIQUE (codigo),
        CONSTRAINT UQ_TipoCancelacionSesion_esAutomatica UNIQUE (esAutomatica)
    );
END
GO
