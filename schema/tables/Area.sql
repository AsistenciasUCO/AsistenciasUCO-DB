USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Area]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Area] (
    [id] uniqueidentifier NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [codigo] nvarchar(3) NOT NULL
);

ALTER TABLE [dbo].[Area] ADD CONSTRAINT [PK__Area__3213E83F4E11A194] PRIMARY KEY CLUSTERED ([id]);
END
GO

-- HU151/HU152: estado del area de conocimiento. Las filas existentes quedan activas.
IF COL_LENGTH('dbo.Area', 'estado') IS NULL
BEGIN
    ALTER TABLE [dbo].[Area] ADD [estado] bit NOT NULL CONSTRAINT [DF_Area_estado] DEFAULT (1);
END
GO

-- HU151/HU152 (D4): unicidad de codigo y nombre (nombre con colacion insensible a mayusculas).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Area_codigo' AND object_id = OBJECT_ID('dbo.Area'))
    CREATE UNIQUE INDEX [UX_Area_codigo] ON [dbo].[Area] ([codigo]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Area_nombre' AND object_id = OBJECT_ID('dbo.Area'))
    CREATE UNIQUE INDEX [UX_Area_nombre] ON [dbo].[Area] ([nombre]);
GO
