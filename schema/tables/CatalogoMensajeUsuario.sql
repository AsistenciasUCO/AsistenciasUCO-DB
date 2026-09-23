USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[CatalogoMensajeUsuario]', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[CatalogoMensajeUsuario] (
        [id]                UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
        [codigo]            VARCHAR(100)     NOT NULL DEFAULT '',
        [tipoMensaje]       VARCHAR(50)      NOT NULL DEFAULT 'BUSINESS_ERROR',
        [severidad]         VARCHAR(20)      NOT NULL DEFAULT 'MEDIO',
        [contenido]         NVARCHAR(4000)   NOT NULL DEFAULT '',
        [estaActivo]        BIT              NOT NULL DEFAULT 1,
        [fechaCreacion]     DATETIME         NOT NULL DEFAULT SYSUTCDATETIME(),
        [fechaModificacion] DATETIME         NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_CatalogoMensajeUsuario] PRIMARY KEY CLUSTERED ([id]),
        CONSTRAINT [UQ_CatalogoMensajeUsuario_Codigo] UNIQUE ([codigo])
    );
END
ELSE
BEGIN
    IF (SELECT COUNT(1) FROM sys.columns WHERE [object_id] = OBJECT_ID('dbo.[CatalogoMensajeUsuario]')) <> 8
       OR EXISTS (
            SELECT 1
            FROM (VALUES
                (N'id',                N'uniqueidentifier', CONVERT(SMALLINT, 16), CONVERT(BIT, 0)),
                (N'codigo',            N'varchar',          CONVERT(SMALLINT, 100), CONVERT(BIT, 0)),
                (N'tipoMensaje',       N'varchar',          CONVERT(SMALLINT, 50), CONVERT(BIT, 0)),
                (N'severidad',         N'varchar',          CONVERT(SMALLINT, 20), CONVERT(BIT, 0)),
                (N'contenido',         N'nvarchar',         CONVERT(SMALLINT, 8000), CONVERT(BIT, 0)),
                (N'estaActivo',        N'bit',              CONVERT(SMALLINT, 1), CONVERT(BIT, 0)),
                (N'fechaCreacion',     N'datetime',         CONVERT(SMALLINT, 8), CONVERT(BIT, 0)),
                (N'fechaModificacion', N'datetime',         CONVERT(SMALLINT, 8), CONVERT(BIT, 0))
            ) AS expected([name], [type_name], [max_length], [is_nullable])
            LEFT JOIN sys.columns c
              ON c.[object_id] = OBJECT_ID('dbo.[CatalogoMensajeUsuario]')
             AND c.[name] = expected.[name]
            LEFT JOIN sys.types t
              ON t.user_type_id = c.user_type_id
            WHERE c.[column_id] IS NULL
               OR t.[name] <> expected.[type_name]
               OR c.[max_length] <> expected.[max_length]
               OR c.[is_nullable] <> expected.[is_nullable]
       )
       OR NOT EXISTS (
            SELECT 1 FROM sys.key_constraints
            WHERE [parent_object_id] = OBJECT_ID('dbo.[CatalogoMensajeUsuario]')
              AND [name] = N'PK_CatalogoMensajeUsuario'
              AND [type] = 'PK'
       )
       OR NOT EXISTS (
            SELECT 1 FROM sys.key_constraints
            WHERE [parent_object_id] = OBJECT_ID('dbo.[CatalogoMensajeUsuario]')
              AND [name] = N'UQ_CatalogoMensajeUsuario_Codigo'
              AND [type] = 'UQ'
       )
    BEGIN
        THROW 51000, 'SCHEMA_CONTRACT_CONFLICT: dbo.CatalogoMensajeUsuario shape differs from DB baseline.', 1;
    END
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE [object_id] = OBJECT_ID('dbo.[CatalogoMensajeUsuario]')
      AND [name] = N'IX_CatalogoMensajeUsuario_Codigo_Activo'
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_CatalogoMensajeUsuario_Codigo_Activo]
    ON [dbo].[CatalogoMensajeUsuario] ([codigo], [estaActivo])
    INCLUDE ([tipoMensaje], [severidad], [contenido]);
END
GO
