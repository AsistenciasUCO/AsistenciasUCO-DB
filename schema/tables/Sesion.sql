USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Sesion]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Sesion] (
    [id] uniqueidentifier NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [numero] int NOT NULL,
    [codigo] nvarchar(50) NOT NULL,
    [numeroSemana] int NOT NULL,
    [grupo] uniqueidentifier NOT NULL,
    [fechaHoraInicio] datetime2 NOT NULL,
    [fechaHoraFin] datetime2 NOT NULL
);

ALTER TABLE [dbo].[Sesion] ADD CONSTRAINT [PK__Sesion__3213E83F33E5FFCB] PRIMARY KEY CLUSTERED ([id]);
END
GO

IF EXISTS (
    SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.Sesion')
      AND name IN (N'au' + N'la', 'descripcion', 'tipo', 'status', 'estado', 'cerrada')
)
    THROW 50004, 'SCHEMA_CONTRACT_CONFLICT: dbo.Sesion contains ghost columns outside DB-GP-001.', 1;
GO

IF EXISTS (
    SELECT grupo, numero
    FROM dbo.Sesion
    GROUP BY grupo, numero
    HAVING COUNT(1) > 1
)
    THROW 50006, 'DATA_INVARIANT_CONFLICT: dbo.Sesion duplicates by grupo/numero.', 1;
GO

IF EXISTS (
    SELECT grupo, codigo
    FROM dbo.Sesion
    GROUP BY grupo, codigo
    HAVING COUNT(1) > 1
)
    THROW 50007, 'DATA_INVARIANT_CONFLICT: dbo.Sesion duplicates by grupo/codigo.', 1;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes i
    JOIN sys.index_columns ic1 ON ic1.object_id = i.object_id AND ic1.index_id = i.index_id AND ic1.key_ordinal = 1
    JOIN sys.columns c1 ON c1.object_id = ic1.object_id AND c1.column_id = ic1.column_id
    JOIN sys.index_columns ic2 ON ic2.object_id = i.object_id AND ic2.index_id = i.index_id AND ic2.key_ordinal = 2
    JOIN sys.columns c2 ON c2.object_id = ic2.object_id AND c2.column_id = ic2.column_id
    WHERE i.object_id = OBJECT_ID('dbo.Sesion')
      AND i.is_unique = 1
      AND c1.name = 'grupo'
      AND c2.name = 'numero'
      AND NOT EXISTS (
          SELECT 1 FROM sys.index_columns icx
          WHERE icx.object_id = i.object_id AND icx.index_id = i.index_id AND icx.key_ordinal > 2
      )
)
    CREATE UNIQUE INDEX UX_Sesion_Grupo_Numero
    ON dbo.Sesion(grupo, numero);
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes i
    JOIN sys.index_columns ic1 ON ic1.object_id = i.object_id AND ic1.index_id = i.index_id AND ic1.key_ordinal = 1
    JOIN sys.columns c1 ON c1.object_id = ic1.object_id AND c1.column_id = ic1.column_id
    JOIN sys.index_columns ic2 ON ic2.object_id = i.object_id AND ic2.index_id = i.index_id AND ic2.key_ordinal = 2
    JOIN sys.columns c2 ON c2.object_id = ic2.object_id AND c2.column_id = ic2.column_id
    WHERE i.object_id = OBJECT_ID('dbo.Sesion')
      AND i.is_unique = 1
      AND c1.name = 'grupo'
      AND c2.name = 'codigo'
      AND NOT EXISTS (
          SELECT 1 FROM sys.index_columns icx
          WHERE icx.object_id = i.object_id AND icx.index_id = i.index_id AND icx.key_ordinal > 2
      )
)
    CREATE UNIQUE INDEX UX_Sesion_Grupo_Codigo
    ON dbo.Sesion(grupo, codigo);
GO
