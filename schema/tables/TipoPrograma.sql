USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[TipoPrograma]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[TipoPrograma] (
    [id] uniqueidentifier NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [estado] bit NOT NULL,
    [codigo] nvarchar(3) NOT NULL
);

ALTER TABLE [dbo].[TipoPrograma] ADD CONSTRAINT [PK__TipoProg__3213E83F40B07414] PRIMARY KEY CLUSTERED ([id]);
END
GO

-- HU154 (D4): unicidad de codigo y nombre.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TipoPrograma_codigo' AND object_id = OBJECT_ID('dbo.TipoPrograma'))
    CREATE UNIQUE INDEX [UX_TipoPrograma_codigo] ON [dbo].[TipoPrograma] ([codigo]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TipoPrograma_nombre' AND object_id = OBJECT_ID('dbo.TipoPrograma'))
    CREATE UNIQUE INDEX [UX_TipoPrograma_nombre] ON [dbo].[TipoPrograma] ([nombre]);
GO
