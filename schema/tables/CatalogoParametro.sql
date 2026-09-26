USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[CatalogoParametro]', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[CatalogoParametro] (
        [id]                UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
        [grupo]             VARCHAR(100)     NOT NULL DEFAULT '',
        [clave]             VARCHAR(100)     NOT NULL DEFAULT '',
        [valor]             NVARCHAR(MAX)    NOT NULL DEFAULT '',
        [tipoDato]          VARCHAR(20)      NOT NULL DEFAULT 'STRING',
        [valorDefecto]      NVARCHAR(MAX)    NOT NULL DEFAULT '',
        [estaActivo]        BIT              NOT NULL DEFAULT 1,
        [fechaCreacion]     DATETIME         NOT NULL DEFAULT SYSUTCDATETIME(),
        [fechaModificacion] DATETIME         NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT [PK_CatalogoParametro] PRIMARY KEY CLUSTERED ([id]),
        CONSTRAINT [UQ_CatalogoParametro_Grupo_Clave] UNIQUE ([grupo], [clave])
    );
END
ELSE
BEGIN
    IF (SELECT COUNT(1) FROM sys.columns WHERE [object_id] = OBJECT_ID('dbo.[CatalogoParametro]')) <> 9
       OR EXISTS (
            SELECT 1
            FROM (VALUES
                (N'id',                N'uniqueidentifier', CONVERT(SMALLINT, 16), CONVERT(BIT, 0)),
                (N'grupo',             N'varchar',          CONVERT(SMALLINT, 100), CONVERT(BIT, 0)),
                (N'clave',             N'varchar',          CONVERT(SMALLINT, 100), CONVERT(BIT, 0)),
                (N'valor',             N'nvarchar',         CONVERT(SMALLINT, -1), CONVERT(BIT, 0)),
                (N'tipoDato',          N'varchar',          CONVERT(SMALLINT, 20), CONVERT(BIT, 0)),
                (N'valorDefecto',      N'nvarchar',         CONVERT(SMALLINT, -1), CONVERT(BIT, 0)),
                (N'estaActivo',        N'bit',              CONVERT(SMALLINT, 1), CONVERT(BIT, 0)),
                (N'fechaCreacion',     N'datetime',         CONVERT(SMALLINT, 8), CONVERT(BIT, 0)),
                (N'fechaModificacion', N'datetime',         CONVERT(SMALLINT, 8), CONVERT(BIT, 0))
            ) AS expected([name], [type_name], [max_length], [is_nullable])
            LEFT JOIN sys.columns c
              ON c.[object_id] = OBJECT_ID('dbo.[CatalogoParametro]')
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
            WHERE [parent_object_id] = OBJECT_ID('dbo.[CatalogoParametro]')
              AND [name] = N'PK_CatalogoParametro'
              AND [type] = 'PK'
       )
       OR NOT EXISTS (
            SELECT 1 FROM sys.key_constraints
            WHERE [parent_object_id] = OBJECT_ID('dbo.[CatalogoParametro]')
              AND [name] = N'UQ_CatalogoParametro_Grupo_Clave'
              AND [type] = 'UQ'
       )
    BEGIN
        THROW 51000, 'SCHEMA_CONTRACT_CONFLICT: dbo.CatalogoParametro shape differs from DB baseline.', 1;
    END
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE [object_id] = OBJECT_ID('dbo.[CatalogoParametro]')
      AND [name] = N'IX_CatalogoParametro_Grupo_Clave_Activo'
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_CatalogoParametro_Grupo_Clave_Activo]
    ON [dbo].[CatalogoParametro] ([grupo], [clave], [estaActivo])
    INCLUDE ([valor], [tipoDato], [valorDefecto]);
END
GO
