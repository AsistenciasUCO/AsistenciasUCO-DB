USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- MIGRACION UP: HU176B - Ventana de matricula por QR/PIN rotativo
-- ============================================================================
-- Los SP usp_abrir_/usp_cerrar_/usp_rotar_ventana..., usp_consultar_ventanas_matricula_por_rotar,
-- usp_validar_token_matricula_publico, usp_matricular_estudiante_por_token, usp_internal_resolver_token_matricula,
-- la vista uv_token_matricula_grupo, los permisos y las semillas (parametros MATRICULA_QR/* y mensajes MQR_*)
-- se despliegan con deploy_schema.ps1 (CREATE OR ALTER / MERGE idempotentes).

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

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TokenMatriculaGrupo_tokenHashAnterior' AND object_id = OBJECT_ID('dbo.TokenMatriculaGrupo'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_TokenMatriculaGrupo_tokenHashAnterior ON dbo.TokenMatriculaGrupo (tokenHashAnterior) WHERE tokenHashAnterior IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TokenMatriculaGrupo_pin_activo' AND object_id = OBJECT_ID('dbo.TokenMatriculaGrupo'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_TokenMatriculaGrupo_pin_activo ON dbo.TokenMatriculaGrupo (pin) WHERE estado = N'ACTIVA';
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TokenMatriculaGrupo_grupo_activo' AND object_id = OBJECT_ID('dbo.TokenMatriculaGrupo'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_TokenMatriculaGrupo_grupo_activo ON dbo.TokenMatriculaGrupo (grupo) WHERE estado = N'ACTIVA';
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_TokenMatriculaGrupo_Grupo')
    ALTER TABLE dbo.TokenMatriculaGrupo ADD CONSTRAINT FK_TokenMatriculaGrupo_Grupo FOREIGN KEY (grupo) REFERENCES dbo.Grupo (id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_TokenMatriculaGrupo_Docente')
    ALTER TABLE dbo.TokenMatriculaGrupo ADD CONSTRAINT FK_TokenMatriculaGrupo_Docente FOREIGN KEY (docenteEmisor) REFERENCES dbo.Docente (id);
GO

-- D6: se retira el SP de matricula autonoma sin RBAC ni transaccion (sin consumidores; lo reemplaza
-- usp_matricular_estudiante_por_token).
IF OBJECT_ID(N'dbo.usp_registrar_estudiante_en_grupo_autonomo', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_registrar_estudiante_en_grupo_autonomo;
GO
