USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.2, DEC-015, HU175/HU176): token y PIN rotativos del QR de asistencia de una toma (analoga a
-- TokenMatriculaGrupo). Solo el SHA-256 del token, nunca el token en claro. El token/PIN anterior vale
-- ASISTENCIA_QR/TOLERANCIA_SEGUNDOS despues de fechaRotacionUtc. fechaExpiracionUtc = fin de la sesion + MARGEN_RETARDO.
-- Sin contador por fila (40 lecturas simultaneas no se serializan sobre el token): el total sale de la vista.
IF OBJECT_ID('dbo.[TokenAsistenciaToma]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.TokenAsistenciaToma (
        id                   UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_TokenAsistenciaToma_id DEFAULT NEWID(),
        toma                 UNIQUEIDENTIFIER NOT NULL,
        docenteEmisor        UNIQUEIDENTIFIER NOT NULL,
        tokenHash            VARBINARY(32)    NOT NULL,
        pin                  NCHAR(6)         NOT NULL,
        tokenHashAnterior    VARBINARY(32)    NULL,
        pinAnterior          NCHAR(6)         NULL,
        fechaEmisionUtc      DATETIME2(0)     NOT NULL,
        fechaRotacionUtc     DATETIME2(0)     NOT NULL,
        fechaExpiracionUtc   DATETIME2(0)     NOT NULL,
        fechaCierreUtc       DATETIME2(0)     NULL,
        idCorrelacionEmision UNIQUEIDENTIFIER NOT NULL,
        CONSTRAINT PK_TokenAsistenciaToma PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_TokenAsistenciaToma_tokenHash UNIQUE (tokenHash),
        CONSTRAINT CK_TokenAsistenciaToma_pin CHECK (pin NOT LIKE N'%[^0-9]%' AND LEN(pin) = 6),
        CONSTRAINT CK_TokenAsistenciaToma_pinAnterior CHECK (pinAnterior IS NULL OR (pinAnterior NOT LIKE N'%[^0-9]%' AND LEN(pinAnterior) = 6)),
        CONSTRAINT CK_TokenAsistenciaToma_fechas CHECK (fechaExpiracionUtc > fechaEmisionUtc AND fechaRotacionUtc >= fechaEmisionUtc)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TokenAsistenciaToma') AND name = 'UX_TokenAsistenciaToma_toma_activo')
    CREATE UNIQUE NONCLUSTERED INDEX UX_TokenAsistenciaToma_toma_activo ON dbo.TokenAsistenciaToma (toma) WHERE fechaCierreUtc IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TokenAsistenciaToma') AND name = 'UX_TokenAsistenciaToma_pin_activo')
    CREATE UNIQUE NONCLUSTERED INDEX UX_TokenAsistenciaToma_pin_activo ON dbo.TokenAsistenciaToma (pin) WHERE fechaCierreUtc IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TokenAsistenciaToma') AND name = 'UX_TokenAsistenciaToma_tokenHashAnterior')
    CREATE UNIQUE NONCLUSTERED INDEX UX_TokenAsistenciaToma_tokenHashAnterior ON dbo.TokenAsistenciaToma (tokenHashAnterior) WHERE tokenHashAnterior IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TokenAsistenciaToma') AND name = 'IX_TokenAsistenciaToma_pinAnterior')
    CREATE NONCLUSTERED INDEX IX_TokenAsistenciaToma_pinAnterior ON dbo.TokenAsistenciaToma (pinAnterior) WHERE pinAnterior IS NOT NULL AND fechaCierreUtc IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TokenAsistenciaToma') AND name = 'IX_TokenAsistenciaToma_rotacion')
    CREATE NONCLUSTERED INDEX IX_TokenAsistenciaToma_rotacion ON dbo.TokenAsistenciaToma (fechaRotacionUtc) INCLUDE (toma, docenteEmisor) WHERE fechaCierreUtc IS NULL;
GO
