USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.3, DEC-011, B-1 de REVIEW-1): un detalle por (asistencia, toma).
--   * toma nace NULL tambien en una instalacion nueva; la semilla 36_backfill_toma_asistencia.sql (y la migracion 16) hace
--     el backfill y el ALTER COLUMN ... NOT NULL. Un solo camino para BD nueva y existente.
--   * Mientras toma admita NULL se conservan el guard 50002 y el indice antiguo UX_DetalleAsistencia_Asistencia; cuando ya
--     es NOT NULL el guard pasa a (asistencia, toma) y se crean (solo entonces) UX_DetalleAsistencia_Asistencia_Toma e
--     IX_DetalleAsistencia_Toma (la FK FK_DetalleAsistencia_TomaAsistencia vive en zz_foreign_keys.sql con la misma
--     condicion). Asi un ALTER COLUMN no choca con dependientes (error 4922).
--   * codigo sale de la secuencia dbo.seq_detalle_asistencia_codigo ([SUPUESTO-B-14]); puede haber huecos tras un rollback.
IF OBJECT_ID('dbo.[DetalleAsistencia]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[DetalleAsistencia] (
    [id] uniqueidentifier NOT NULL,
    [codigo] int NOT NULL,
    [asistencia] uniqueidentifier NOT NULL,
    [asistio] bit NOT NULL,
    [razonCausa] uniqueidentifier NOT NULL,
    [fechaHoraInicio] datetime2 NOT NULL,
    [fechaHoraFin] datetime2 NOT NULL,
    [toma] uniqueidentifier NULL,
    [registradoPorEstudiante] bit NOT NULL CONSTRAINT DF_DetalleAsistencia_registradoPorEstudiante DEFAULT 0,
    [fechaRegistroUtc] datetime2(0) NULL
);

ALTER TABLE [dbo].[DetalleAsistencia] ADD CONSTRAINT [PK__DetalleA__3213E83F60851D6A] PRIMARY KEY CLUSTERED ([id]);
END
GO

-- BD existente (idempotente): columnas de B.2
IF COL_LENGTH('dbo.DetalleAsistencia', 'toma') IS NULL
    ALTER TABLE dbo.DetalleAsistencia ADD [toma] uniqueidentifier NULL;
IF COL_LENGTH('dbo.DetalleAsistencia', 'registradoPorEstudiante') IS NULL
    ALTER TABLE dbo.DetalleAsistencia ADD [registradoPorEstudiante] bit NOT NULL
        CONSTRAINT DF_DetalleAsistencia_registradoPorEstudiante DEFAULT 0;
IF COL_LENGTH('dbo.DetalleAsistencia', 'fechaRegistroUtc') IS NULL
    ALTER TABLE dbo.DetalleAsistencia ADD [fechaRegistroUtc] datetime2(0) NULL;
GO

-- (c) Antes del backfill (toma admite NULL): guard e indice antiguos por asistencia
IF COLUMNPROPERTY(OBJECT_ID('dbo.DetalleAsistencia'), 'toma', 'AllowsNull') = 1
BEGIN
    IF EXISTS (
        SELECT asistencia
        FROM dbo.DetalleAsistencia
        GROUP BY asistencia
        HAVING COUNT(1) > 1
    )
        THROW 50002, 'DATA_INVARIANT_CONFLICT: dbo.DetalleAsistencia duplicates by asistencia.', 1;

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
END
GO

-- (a) Despues del backfill (toma NOT NULL): guard por (asistencia, toma) y dependientes de toma
IF COLUMNPROPERTY(OBJECT_ID('dbo.DetalleAsistencia'), 'toma', 'AllowsNull') = 0
BEGIN
    IF EXISTS (
        SELECT asistencia, toma
        FROM dbo.DetalleAsistencia
        GROUP BY asistencia, toma
        HAVING COUNT(1) > 1
    )
        THROW 50002, 'DATA_INVARIANT_CONFLICT: dbo.DetalleAsistencia duplicates by (asistencia, toma).', 1;

    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_DetalleAsistencia_Asistencia_Toma' AND object_id = OBJECT_ID('dbo.DetalleAsistencia'))
        CREATE UNIQUE NONCLUSTERED INDEX UX_DetalleAsistencia_Asistencia_Toma ON dbo.DetalleAsistencia (asistencia, toma);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_DetalleAsistencia_Toma' AND object_id = OBJECT_ID('dbo.DetalleAsistencia'))
        CREATE NONCLUSTERED INDEX IX_DetalleAsistencia_Toma ON dbo.DetalleAsistencia (toma) INCLUDE (asistencia, asistio, razonCausa);
END
GO

-- Secuencia de DetalleAsistencia.codigo ([SUPUESTO-B-14]): START WITH = MAX(codigo) + 1 calculado en el momento
IF OBJECT_ID('dbo.seq_detalle_asistencia_codigo', 'SO') IS NULL
BEGIN
    DECLARE @inicioSecuencia BIGINT = (SELECT ISNULL(MAX(CAST(codigo AS BIGINT)), 0) + 1 FROM dbo.DetalleAsistencia);
    DECLARE @sqlSecuencia NVARCHAR(400) = CONCAT(N'CREATE SEQUENCE dbo.seq_detalle_asistencia_codigo AS INT START WITH ', @inicioSecuencia,
                                                N' INCREMENT BY 1 NO CYCLE CACHE 50;');
    EXEC sys.sp_executesql @sqlSecuencia;
END
GO
