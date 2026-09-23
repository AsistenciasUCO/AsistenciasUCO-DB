USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[RazonCausa]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[RazonCausa] (
    [id] uniqueidentifier NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [codigo] nvarchar(5) NOT NULL
);

ALTER TABLE [dbo].[RazonCausa] ADD CONSTRAINT [PK__RazonCau__3213E83F8D311926] PRIMARY KEY CLUSTERED ([id]);
END
GO

IF EXISTS (
    SELECT codigo
    FROM dbo.RazonCausa
    GROUP BY codigo
    HAVING COUNT(1) > 1
)
    THROW 50003, 'DATA_INVARIANT_CONFLICT: dbo.RazonCausa duplicates by codigo.', 1;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes i
    JOIN sys.index_columns ic1 ON ic1.object_id = i.object_id AND ic1.index_id = i.index_id AND ic1.key_ordinal = 1
    JOIN sys.columns c1 ON c1.object_id = ic1.object_id AND c1.column_id = ic1.column_id
    WHERE i.object_id = OBJECT_ID('dbo.RazonCausa')
      AND i.is_unique = 1
      AND c1.name = 'codigo'
      AND NOT EXISTS (
          SELECT 1 FROM sys.index_columns icx
          WHERE icx.object_id = i.object_id AND icx.index_id = i.index_id AND icx.key_ordinal > 1
      )
)
    CREATE UNIQUE INDEX UX_RazonCausa_Codigo
    ON dbo.RazonCausa(codigo);
GO
