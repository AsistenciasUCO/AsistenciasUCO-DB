USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[DetalleAsistencia]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[DetalleAsistencia] (
    [id] uniqueidentifier NOT NULL,
    [codigo] int NOT NULL,
    [asistencia] uniqueidentifier NOT NULL,
    [asistio] bit NOT NULL,
    [razonCausa] uniqueidentifier NOT NULL,
    [fechaHoraInicio] datetime2 NOT NULL,
    [fechaHoraFin] datetime2 NOT NULL
);

ALTER TABLE [dbo].[DetalleAsistencia] ADD CONSTRAINT [PK__DetalleA__3213E83F60851D6A] PRIMARY KEY CLUSTERED ([id]);
END
GO

IF EXISTS (
    SELECT asistencia
    FROM dbo.DetalleAsistencia
    GROUP BY asistencia
    HAVING COUNT(1) > 1
)
    THROW 50002, 'DATA_INVARIANT_CONFLICT: dbo.DetalleAsistencia duplicates by asistencia.', 1;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes i
    JOIN sys.index_columns ic1 ON ic1.object_id = i.object_id AND ic1.index_id = i.index_id AND ic1.key_ordinal = 1
    JOIN sys.columns c1 ON c1.object_id = ic1.object_id AND c1.column_id = ic1.column_id
    WHERE i.object_id = OBJECT_ID('dbo.DetalleAsistencia')
      AND i.is_unique = 1
      AND c1.name = 'asistencia'
      AND NOT EXISTS (
          SELECT 1 FROM sys.index_columns icx
          WHERE icx.object_id = i.object_id AND icx.index_id = i.index_id AND icx.key_ordinal > 1
      )
)
    CREATE UNIQUE INDEX UX_DetalleAsistencia_Asistencia
    ON dbo.DetalleAsistencia(asistencia);
GO
