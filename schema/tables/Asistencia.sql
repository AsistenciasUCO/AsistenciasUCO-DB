USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[Asistencia]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[Asistencia] (
    [id] uniqueidentifier NOT NULL,
    [estudianteGrupo] uniqueidentifier NOT NULL,
    [sesion] uniqueidentifier NOT NULL
);

ALTER TABLE [dbo].[Asistencia] ADD CONSTRAINT [PK__Asistenc__3213E83F4635E5C7] PRIMARY KEY CLUSTERED ([id]);
END
GO

IF EXISTS (
    SELECT estudianteGrupo, sesion
    FROM dbo.Asistencia
    GROUP BY estudianteGrupo, sesion
    HAVING COUNT(1) > 1
)
    THROW 50001, 'DATA_INVARIANT_CONFLICT: dbo.Asistencia duplicates by estudianteGrupo/sesion.', 1;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes i
    JOIN sys.index_columns ic1 ON ic1.object_id = i.object_id AND ic1.index_id = i.index_id AND ic1.key_ordinal = 1
    JOIN sys.columns c1 ON c1.object_id = ic1.object_id AND c1.column_id = ic1.column_id
    JOIN sys.index_columns ic2 ON ic2.object_id = i.object_id AND ic2.index_id = i.index_id AND ic2.key_ordinal = 2
    JOIN sys.columns c2 ON c2.object_id = ic2.object_id AND c2.column_id = ic2.column_id
    WHERE i.object_id = OBJECT_ID('dbo.Asistencia')
      AND i.is_unique = 1
      AND c1.name = 'estudianteGrupo'
      AND c2.name = 'sesion'
      AND NOT EXISTS (
          SELECT 1 FROM sys.index_columns icx
          WHERE icx.object_id = i.object_id AND icx.index_id = i.index_id AND icx.key_ordinal > 2
      )
)
    CREATE UNIQUE INDEX UX_Asistencia_EstudianteGrupo_Sesion
    ON dbo.Asistencia(estudianteGrupo, sesion);
GO
