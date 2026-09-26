USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Grupo]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Grupo] (
    [id] uniqueidentifier NOT NULL,
    [asignatura] uniqueidentifier NOT NULL,
    [periodoAcademico] uniqueidentifier NOT NULL,
    [codigo] int NOT NULL,
    [nombre] nvarchar(50) NOT NULL,
    [cantidadEstudiantes] int NOT NULL,
    [cantidadEstudiantesFinalizaron] int NOT NULL,
    [cantidadEstudiantesCancelaronVoluntadPropia] int NOT NULL,
    [cantidadEstudiantesCancelaronAutomaticamente] int NOT NULL,
    [docente] uniqueidentifier NOT NULL
);

ALTER TABLE [dbo].[Grupo] ADD CONSTRAINT [PK__Grupo__3213E83FFA8811CC] PRIMARY KEY CLUSTERED ([id]);
END
GO

IF EXISTS (
    SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.Grupo')
      AND name IN (N'au' + N'la')
)
    THROW 50005, 'SCHEMA_CONTRACT_CONFLICT: dbo.Grupo contains ghost columns outside DB-GP-001.', 1;
GO
