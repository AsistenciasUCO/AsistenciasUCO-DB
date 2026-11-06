USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU176B: ventana de matricula por QR/PIN (una fila por ventana abierta por el docente). El token rota cada
-- MATRICULA_QR/ROTACION_SEGUNDOS: la fila guarda el token vigente y el inmediatamente anterior (tolerancia).
-- Solo se guarda el SHA-256 del token; el token en claro nunca se persiste.
-- estado: ACTIVA / CERRADA / EXPIRADA (valores de los parametros MATRICULA_QR/ESTADO_*).
IF OBJECT_ID('dbo.TokenMatriculaGrupo', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.TokenMatriculaGrupo (
        id                 UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_TokenMatriculaGrupo_id DEFAULT NEWID(),
        grupo              UNIQUEIDENTIFIER NOT NULL,
        docenteEmisor      UNIQUEIDENTIFIER NOT NULL,
        tokenHash          VARBINARY(32)    NOT NULL,
        pin                NCHAR(6)         NOT NULL,
        tokenHashAnterior  VARBINARY(32)    NULL,
        pinAnterior        NCHAR(6)         NULL,
        fechaRotacionUtc   DATETIME2(0)     NOT NULL,
        estado             NVARCHAR(10)     NOT NULL,
        fechaEmisionUtc    DATETIME2(0)     NOT NULL,
        fechaExpiracionUtc DATETIME2(0)     NOT NULL,
        fechaCierreUtc     DATETIME2(0)     NULL,
        totalMatriculas    INT              NOT NULL CONSTRAINT DF_TokenMatriculaGrupo_total DEFAULT 0,
        CONSTRAINT PK_TokenMatriculaGrupo PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_TokenMatriculaGrupo_tokenHash UNIQUE (tokenHash),
        CONSTRAINT CK_TokenMatriculaGrupo_pin CHECK (pin NOT LIKE N'%[^0-9]%' AND LEN(pin) = 6)
    );
END
GO

-- Un token anterior solo puede pertenecer a una fila.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TokenMatriculaGrupo_tokenHashAnterior' AND object_id = OBJECT_ID('dbo.TokenMatriculaGrupo'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_TokenMatriculaGrupo_tokenHashAnterior
    ON dbo.TokenMatriculaGrupo (tokenHashAnterior)
    WHERE tokenHashAnterior IS NOT NULL;
END
GO

-- Unicidad fisica del PIN vigente y de la ventana por grupo entre las ventanas ACTIVAS.
-- El literal del filtro es el valor del parametro MATRICULA_QR/ESTADO_ACTIVA: unica excepcion tecnica documentada
-- (CONTRACT §2.2). La unicidad del PIN frente a los PIN anteriores se garantiza en usp_abrir_/usp_rotar_ (UPDLOCK, HOLDLOCK).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TokenMatriculaGrupo_pin_activo' AND object_id = OBJECT_ID('dbo.TokenMatriculaGrupo'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_TokenMatriculaGrupo_pin_activo
    ON dbo.TokenMatriculaGrupo (pin)
    WHERE estado = N'ACTIVA';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TokenMatriculaGrupo_grupo_activo' AND object_id = OBJECT_ID('dbo.TokenMatriculaGrupo'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_TokenMatriculaGrupo_grupo_activo
    ON dbo.TokenMatriculaGrupo (grupo)
    WHERE estado = N'ACTIVA';
END
GO
