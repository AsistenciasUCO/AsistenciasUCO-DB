USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- CULM-001 B.2 - Migracion 16 UP: tomas de asistencia por horas y QR de asistencia por toma (CONTRACT §2.14).
-- Idempotente (B2-MIG-02). Cubre el cambio de estructura y de datos de una BD existente; los SP, las semillas de
-- parametros/mensajes y los permisos de EXECUTE los despliega deploy_schema.ps1 (CREATE OR ALTER / MERGE).
--   1. ModoTomaAsistencia, EstadoTomaAsistencia (+ filas con ids fijos), TomaAsistencia, TokenAsistenciaToma (indices y FKs).
--   2. DetalleAsistencia.toma (NULL), registradoPorEstudiante, fechaRegistroUtc; secuencia seq_detalle_asistencia_codigo con
--      START WITH = MAX(codigo) + 1 (SQL dinamico), igual que schema/tables/DetalleAsistencia.sql.
--   3. Conversion a NOT NULL en una transaccion (B-1): aborta con 50010 si hay mas de un detalle por asistencia; backfill de la
--      toma 1 implicita (MANUAL, CERRADA) por sesion con detalles; borra dependientes; ALTER COLUMN NOT NULL; borra
--      UX_DetalleAsistencia_Asistencia; recrea UX_DetalleAsistencia_Asistencia_Toma, IX_DetalleAsistencia_Toma y la FK.
--      (Mismo texto que schema/seed/36_backfill_toma_asistencia.sql.)
--   4. Resultset de control: tomasCreadas, detallesAsignados, detallesSinToma (= 0), detallesIncoherentes (asistio distinto
--      de codigo = AN, F-DOC-012, solo reporte), sesionesConCabeceraSinDetalle (NB-9), siguienteCodigoSecuencia,
--      maxCodigoDetalle.
--   5. Funciones de horas y vistas de B.2 (nuevas y modificadas) + GRANT SELECT de las vistas nuevas.
-- ============================================================================
SET NOCOUNT ON;
IF OBJECT_ID(N'tempdb..#culm001b2Mig16') IS NOT NULL DROP TABLE #culm001b2Mig16;
CREATE TABLE #culm001b2Mig16 (tomasAntes INT NULL, detallesSinTomaAntes INT NULL);
INSERT INTO #culm001b2Mig16 (tomasAntes, detallesSinTomaAntes)
SELECT IIF(OBJECT_ID(N'dbo.TomaAsistencia', N'U') IS NULL, 0, NULL), NULL;
IF OBJECT_ID(N'dbo.TomaAsistencia', N'U') IS NOT NULL
    EXEC sys.sp_executesql N'UPDATE #culm001b2Mig16 SET tomasAntes = (SELECT COUNT(1) FROM dbo.TomaAsistencia);';
GO

-- ---------------------------------------------------------------------------------------------------------------
-- 1-2. Tablas, columnas, indices y secuencia
-- ---------------------------------------------------------------------------------------------------------------
-- schema/tables/ModoTomaAsistencia.sql
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.1): modo de una toma de asistencia (MANUAL | QR). Los SP lo resuelven por las banderas
-- usaCodigoQr (unica) y marcaAusentesAlCerrar (valor por defecto de @marcarAusentes al cerrar), nunca por el codigo.
-- Filas con ids fijos en la semilla 35_catalogos_toma_asistencia.sql.
IF OBJECT_ID('dbo.[ModoTomaAsistencia]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.ModoTomaAsistencia (
        id                     UNIQUEIDENTIFIER NOT NULL,
        codigo                 NVARCHAR(20)     NOT NULL,
        nombre                 NVARCHAR(50)     NOT NULL,
        usaCodigoQr            BIT              NOT NULL,
        marcaAusentesAlCerrar  BIT              NOT NULL,
        CONSTRAINT PK_ModoTomaAsistencia PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_ModoTomaAsistencia_codigo UNIQUE (codigo),
        CONSTRAINT UQ_ModoTomaAsistencia_usaCodigoQr UNIQUE (usaCodigoQr)
    );
END
GO

-- schema/tables/EstadoTomaAsistencia.sql
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.1): estado de una toma de asistencia (ABIERTA | CERRADA), resuelto por la bandera estaAbierta
-- (unica). Invariante INV_TOMA_ESTADO_CIERRE: estaAbierta = 1 <=> TomaAsistencia.fechaCierreUtc IS NULL.
IF OBJECT_ID('dbo.[EstadoTomaAsistencia]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.EstadoTomaAsistencia (
        id           UNIQUEIDENTIFIER NOT NULL,
        codigo       NVARCHAR(20)     NOT NULL,
        nombre       NVARCHAR(50)     NOT NULL,
        estaAbierta  BIT              NOT NULL,
        CONSTRAINT PK_EstadoTomaAsistencia PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_EstadoTomaAsistencia_codigo UNIQUE (codigo),
        CONSTRAINT UQ_EstadoTomaAsistencia_estaAbierta UNIQUE (estaAbierta)
    );
END
GO

-- schema/tables/TomaAsistencia.sql
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.2, DEC-011, DEC-013): toma de asistencia de una sesion. Una sesion tiene de 0 a
-- TOMA_ASISTENCIA/MAXIMO_TOMAS_POR_SESION tomas numeradas 1..n; a lo sumo una ABIERTA (indice filtrado por
-- fechaCierreUtc IS NULL, sin literal de estado). esImplicita = 1: toma creada por el lote legado o por el backfill
-- (nace CERRADA). docenteApertura NULL solo en el backfill.
IF OBJECT_ID('dbo.[TomaAsistencia]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.TomaAsistencia (
        id                     UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_TomaAsistencia_id DEFAULT NEWID(),
        sesion                 UNIQUEIDENTIFIER NOT NULL,
        numero                 SMALLINT         NOT NULL,
        modo                   UNIQUEIDENTIFIER NOT NULL,
        estado                 UNIQUEIDENTIFIER NOT NULL,
        esImplicita            BIT              NOT NULL CONSTRAINT DF_TomaAsistencia_esImplicita DEFAULT 0,
        docenteApertura        UNIQUEIDENTIFIER NULL,
        fechaAperturaUtc       DATETIME2(0)     NOT NULL,
        fechaCierreUtc         DATETIME2(0)     NULL,
        totalAusentesMarcados  INT              NOT NULL CONSTRAINT DF_TomaAsistencia_ausentes DEFAULT 0,
        idCorrelacionApertura  UNIQUEIDENTIFIER NOT NULL,
        idCorrelacionCierre    UNIQUEIDENTIFIER NULL,
        CONSTRAINT PK_TomaAsistencia PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_TomaAsistencia_Sesion_Numero UNIQUE (sesion, numero),
        CONSTRAINT CK_TomaAsistencia_numero CHECK (numero >= 1),
        CONSTRAINT CK_TomaAsistencia_cierre CHECK (fechaCierreUtc IS NULL OR fechaCierreUtc >= fechaAperturaUtc),
        CONSTRAINT CK_TomaAsistencia_ausentes CHECK (totalAusentesMarcados >= 0)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TomaAsistencia') AND name = 'UX_TomaAsistencia_Sesion_Abierta')
    CREATE UNIQUE NONCLUSTERED INDEX UX_TomaAsistencia_Sesion_Abierta ON dbo.TomaAsistencia (sesion) WHERE fechaCierreUtc IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TomaAsistencia') AND name = 'IX_TomaAsistencia_abiertas')
    CREATE NONCLUSTERED INDEX IX_TomaAsistencia_abiertas ON dbo.TomaAsistencia (fechaAperturaUtc) INCLUDE (sesion, modo) WHERE fechaCierreUtc IS NULL;
GO

-- schema/tables/TokenAsistenciaToma.sql
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.2, DEC-015, HU175/HU176): token y PIN rotativos del QR de asistencia de una toma (analoga a
-- TokenMatriculaGrupo). Solo el SHA-256 del token, nunca el token en claro. El token/PIN anterior vale
-- ASISTENCIA_QR/TOLERANCIA_SEGUNDOS despues de fechaRotacionUtc. fechaExpiracionUtc = fin de la sesion + MARGEN_RETARDO.
-- Sin contador por fila (40 lecturas simultaneas no se serializan sobre el token): el total sale de la vista.
IF OBJECT_ID('dbo.[TokenAsistenciaToma]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.TokenAsistenciaToma (
        id                   UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_TokenAsistenciaToma_id DEFAULT NEWID(),
        toma                 UNIQUEIDENTIFIER NOT NULL,
        docenteEmisor        UNIQUEIDENTIFIER NOT NULL,
        tokenHash            VARBINARY(32)    NOT NULL,
        pin                  NCHAR(6)         NOT NULL,
        tokenHashAnterior    VARBINARY(32)    NULL,
        pinAnterior          NCHAR(6)         NULL,
        fechaEmisionUtc      DATETIME2(0)     NOT NULL,
        fechaRotacionUtc     DATETIME2(0)     NOT NULL,
        fechaExpiracionUtc   DATETIME2(0)     NOT NULL,
        fechaCierreUtc       DATETIME2(0)     NULL,
        idCorrelacionEmision UNIQUEIDENTIFIER NOT NULL,
        CONSTRAINT PK_TokenAsistenciaToma PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_TokenAsistenciaToma_tokenHash UNIQUE (tokenHash),
        CONSTRAINT CK_TokenAsistenciaToma_pin CHECK (pin NOT LIKE N'%[^0-9]%' AND LEN(pin) = 6),
        CONSTRAINT CK_TokenAsistenciaToma_pinAnterior CHECK (pinAnterior IS NULL OR (pinAnterior NOT LIKE N'%[^0-9]%' AND LEN(pinAnterior) = 6)),
        CONSTRAINT CK_TokenAsistenciaToma_fechas CHECK (fechaExpiracionUtc > fechaEmisionUtc AND fechaRotacionUtc >= fechaEmisionUtc)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TokenAsistenciaToma') AND name = 'UX_TokenAsistenciaToma_toma_activo')
    CREATE UNIQUE NONCLUSTERED INDEX UX_TokenAsistenciaToma_toma_activo ON dbo.TokenAsistenciaToma (toma) WHERE fechaCierreUtc IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TokenAsistenciaToma') AND name = 'UX_TokenAsistenciaToma_pin_activo')
    CREATE UNIQUE NONCLUSTERED INDEX UX_TokenAsistenciaToma_pin_activo ON dbo.TokenAsistenciaToma (pin) WHERE fechaCierreUtc IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TokenAsistenciaToma') AND name = 'UX_TokenAsistenciaToma_tokenHashAnterior')
    CREATE UNIQUE NONCLUSTERED INDEX UX_TokenAsistenciaToma_tokenHashAnterior ON dbo.TokenAsistenciaToma (tokenHashAnterior) WHERE tokenHashAnterior IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TokenAsistenciaToma') AND name = 'IX_TokenAsistenciaToma_pinAnterior')
    CREATE NONCLUSTERED INDEX IX_TokenAsistenciaToma_pinAnterior ON dbo.TokenAsistenciaToma (pinAnterior) WHERE pinAnterior IS NOT NULL AND fechaCierreUtc IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.TokenAsistenciaToma') AND name = 'IX_TokenAsistenciaToma_rotacion')
    CREATE NONCLUSTERED INDEX IX_TokenAsistenciaToma_rotacion ON dbo.TokenAsistenciaToma (fechaRotacionUtc) INCLUDE (toma, docenteEmisor) WHERE fechaCierreUtc IS NULL;
GO

-- schema/tables/DetalleAsistencia.sql
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

-- FKs de B.2 (bloque B.2 de schema/tables/zz_foreign_keys.sql)
-- CULM-001 B.2 (CONTRACT §2.2, §2.3): tomas de asistencia y tokens QR por toma
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_TomaAsistencia_Sesion')
BEGIN
    ALTER TABLE [dbo].[TomaAsistencia] ADD CONSTRAINT [FK_TomaAsistencia_Sesion] FOREIGN KEY ([sesion]) REFERENCES [dbo].[Sesion] ([id]);
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_TomaAsistencia_ModoTomaAsistencia')
BEGIN
    ALTER TABLE [dbo].[TomaAsistencia] ADD CONSTRAINT [FK_TomaAsistencia_ModoTomaAsistencia] FOREIGN KEY ([modo]) REFERENCES [dbo].[ModoTomaAsistencia] ([id]);
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_TomaAsistencia_EstadoTomaAsistencia')
BEGIN
    ALTER TABLE [dbo].[TomaAsistencia] ADD CONSTRAINT [FK_TomaAsistencia_EstadoTomaAsistencia] FOREIGN KEY ([estado]) REFERENCES [dbo].[EstadoTomaAsistencia] ([id]);
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_TomaAsistencia_Docente')
BEGIN
    ALTER TABLE [dbo].[TomaAsistencia] ADD CONSTRAINT [FK_TomaAsistencia_Docente] FOREIGN KEY ([docenteApertura]) REFERENCES [dbo].[Docente] ([id]);
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_TokenAsistenciaToma_TomaAsistencia')
BEGIN
    ALTER TABLE [dbo].[TokenAsistenciaToma] ADD CONSTRAINT [FK_TokenAsistenciaToma_TomaAsistencia] FOREIGN KEY ([toma]) REFERENCES [dbo].[TomaAsistencia] ([id]);
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_TokenAsistenciaToma_Docente')
BEGIN
    ALTER TABLE [dbo].[TokenAsistenciaToma] ADD CONSTRAINT [FK_TokenAsistenciaToma_Docente] FOREIGN KEY ([docenteEmisor]) REFERENCES [dbo].[Docente] ([id]);
END
GO
-- Dependiente de DetalleAsistencia.toma: solo cuando la columna ya es NOT NULL (B-1: evita el error 4922 en el ALTER COLUMN)
IF COLUMNPROPERTY(OBJECT_ID('dbo.DetalleAsistencia'), 'toma', 'AllowsNull') = 0
   AND NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_DetalleAsistencia_TomaAsistencia')
BEGIN
    ALTER TABLE [dbo].[DetalleAsistencia] ADD CONSTRAINT [FK_DetalleAsistencia_TomaAsistencia] FOREIGN KEY ([toma]) REFERENCES [dbo].[TomaAsistencia] ([id]);
END
GO

-- Filas de los catalogos (schema/seed/35_catalogos_toma_asistencia.sql)
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.1): catalogos ModoTomaAsistencia y EstadoTomaAsistencia con ids fijos (patron 08_razon_causa.sql).
-- Idempotente. Los SP los resuelven por las banderas usaCodigoQr / marcaAusentesAlCerrar / estaAbierta, nunca por el codigo.
MERGE INTO [dbo].[ModoTomaAsistencia] AS Target
USING (VALUES
    (CAST('7C1E0B20-5E51-4C0A-9A01-000000000001' AS UNIQUEIDENTIFIER), N'MANUAL', N'Registro manual del docente', CAST(0 AS BIT), CAST(0 AS BIT)),
    (CAST('7C1E0B20-5E51-4C0A-9A01-000000000002' AS UNIQUEIDENTIFIER), N'QR',     N'Código QR y PIN rotativos',  CAST(1 AS BIT), CAST(1 AS BIT))
) AS Source (id, codigo, nombre, usaCodigoQr, marcaAusentesAlCerrar)
ON (Target.id = Source.id)
WHEN MATCHED THEN
    UPDATE SET Target.codigo = Source.codigo, Target.nombre = Source.nombre, Target.usaCodigoQr = Source.usaCodigoQr,
               Target.marcaAusentesAlCerrar = Source.marcaAusentesAlCerrar
WHEN NOT MATCHED THEN
    INSERT (id, codigo, nombre, usaCodigoQr, marcaAusentesAlCerrar)
    VALUES (Source.id, Source.codigo, Source.nombre, Source.usaCodigoQr, Source.marcaAusentesAlCerrar);
GO

MERGE INTO [dbo].[EstadoTomaAsistencia] AS Target
USING (VALUES
    (CAST('7C1E0B30-5E51-4C0A-9A01-000000000001' AS UNIQUEIDENTIFIER), N'ABIERTA', N'Abierta', CAST(1 AS BIT)),
    (CAST('7C1E0B30-5E51-4C0A-9A01-000000000002' AS UNIQUEIDENTIFIER), N'CERRADA', N'Cerrada', CAST(0 AS BIT))
) AS Source (id, codigo, nombre, estaAbierta)
ON (Target.id = Source.id)
WHEN MATCHED THEN
    UPDATE SET Target.codigo = Source.codigo, Target.nombre = Source.nombre, Target.estaAbierta = Source.estaAbierta
WHEN NOT MATCHED THEN
    INSERT (id, codigo, nombre, estaAbierta)
    VALUES (Source.id, Source.codigo, Source.nombre, Source.estaAbierta);
GO

SET NOCOUNT ON;
IF COL_LENGTH('dbo.DetalleAsistencia', 'toma') IS NOT NULL
    EXEC sys.sp_executesql N'UPDATE #culm001b2Mig16 SET detallesSinTomaAntes = (SELECT COUNT(1) FROM dbo.DetalleAsistencia WHERE toma IS NULL);';
GO

-- ---------------------------------------------------------------------------------------------------------------
-- 3. Conversion de DetalleAsistencia.toma a NOT NULL (orden exacto de B-1) y realineacion de la secuencia
-- ---------------------------------------------------------------------------------------------------------------
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF COLUMNPROPERTY(OBJECT_ID('dbo.DetalleAsistencia'), 'toma', 'AllowsNull') = 1
BEGIN
    BEGIN TRANSACTION;

    IF EXISTS (SELECT asistencia FROM dbo.DetalleAsistencia GROUP BY asistencia HAVING COUNT(1) > 1)
        THROW 50010, 'CULM001_B2_BACKFILL: DetalleAsistencia tiene mas de un detalle por asistencia antes de la conversion.', 1;

    EXEC sys.sp_executesql N'
        DECLARE @idCorrelacionMigracion UNIQUEIDENTIFIER = NEWID();
        DECLARE @modoManual UNIQUEIDENTIFIER = (SELECT m.id FROM dbo.ModoTomaAsistencia m WHERE m.usaCodigoQr = 0);
        DECLARE @estadoCerrada UNIQUEIDENTIFIER = (SELECT e.id FROM dbo.EstadoTomaAsistencia e WHERE e.estaAbierta = 0);
        IF EXISTS (SELECT 1 FROM dbo.DetalleAsistencia WHERE toma IS NULL) AND (@modoManual IS NULL OR @estadoCerrada IS NULL)
            THROW 50012, ''CULM001_B2_BACKFILL: faltan los catalogos ModoTomaAsistencia / EstadoTomaAsistencia (semilla 35).'', 1;
        INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc,
                                        totalAusentesMarcados, idCorrelacionApertura, idCorrelacionCierre)
        SELECT NEWID(), s.id, 1, @modoManual, @estadoCerrada, 1, g.docente, CAST(s.fechaHoraInicio AS DATETIME2(0)),
               CAST(IIF(s.fechaHoraFin > s.fechaHoraInicio, s.fechaHoraFin, s.fechaHoraInicio) AS DATETIME2(0)), 0, @idCorrelacionMigracion, @idCorrelacionMigracion
        FROM dbo.Sesion s
        INNER JOIN dbo.Grupo g ON g.id = s.grupo
        WHERE EXISTS (SELECT 1 FROM dbo.DetalleAsistencia da INNER JOIN dbo.Asistencia a ON a.id = da.asistencia
                      WHERE a.sesion = s.id AND da.toma IS NULL)
          AND NOT EXISTS (SELECT 1 FROM dbo.TomaAsistencia t WHERE t.sesion = s.id AND t.numero = 1);
        UPDATE da SET toma = t.id
        FROM dbo.DetalleAsistencia da
        INNER JOIN dbo.Asistencia a ON a.id = da.asistencia
        INNER JOIN dbo.TomaAsistencia t ON t.sesion = a.sesion AND t.numero = 1
        WHERE da.toma IS NULL;';

    IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_DetalleAsistencia_TomaAsistencia')
        ALTER TABLE dbo.DetalleAsistencia DROP CONSTRAINT FK_DetalleAsistencia_TomaAsistencia;
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_DetalleAsistencia_Asistencia_Toma' AND object_id = OBJECT_ID('dbo.DetalleAsistencia'))
        DROP INDEX UX_DetalleAsistencia_Asistencia_Toma ON dbo.DetalleAsistencia;
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_DetalleAsistencia_Toma' AND object_id = OBJECT_ID('dbo.DetalleAsistencia'))
        DROP INDEX IX_DetalleAsistencia_Toma ON dbo.DetalleAsistencia;

    EXEC sys.sp_executesql N'ALTER TABLE dbo.DetalleAsistencia ALTER COLUMN toma uniqueidentifier NOT NULL;';

    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_DetalleAsistencia_Asistencia' AND object_id = OBJECT_ID('dbo.DetalleAsistencia'))
        DROP INDEX UX_DetalleAsistencia_Asistencia ON dbo.DetalleAsistencia;

    EXEC sys.sp_executesql N'CREATE UNIQUE NONCLUSTERED INDEX UX_DetalleAsistencia_Asistencia_Toma ON dbo.DetalleAsistencia (asistencia, toma);';
    EXEC sys.sp_executesql N'CREATE NONCLUSTERED INDEX IX_DetalleAsistencia_Toma ON dbo.DetalleAsistencia (toma) INCLUDE (asistencia, asistio, razonCausa);';
    EXEC sys.sp_executesql N'ALTER TABLE dbo.DetalleAsistencia ADD CONSTRAINT FK_DetalleAsistencia_TomaAsistencia FOREIGN KEY (toma) REFERENCES dbo.TomaAsistencia (id);';

    COMMIT TRANSACTION;
END
GO

-- Secuencia de codigo: creada por DetalleAsistencia.sql; se realinea si quedo por detras del maximo (filas insertadas con
-- codigo explicito despues de crearla).
SET NOCOUNT ON;
IF OBJECT_ID('dbo.seq_detalle_asistencia_codigo', 'SO') IS NOT NULL
BEGIN
    DECLARE @maximoCodigo BIGINT = (SELECT ISNULL(MAX(CAST(codigo AS BIGINT)), 0) FROM dbo.DetalleAsistencia);
    IF (SELECT CAST(current_value AS BIGINT) FROM sys.sequences WHERE object_id = OBJECT_ID('dbo.seq_detalle_asistencia_codigo')) < @maximoCodigo
    BEGIN
        DECLARE @sqlReinicio NVARCHAR(400) = CONCAT(N'ALTER SEQUENCE dbo.seq_detalle_asistencia_codigo RESTART WITH ', @maximoCodigo + 1, N';');
        EXEC sys.sp_executesql @sqlReinicio;
    END
END
GO

-- ---------------------------------------------------------------------------------------------------------------
-- 4. Resultset de control
-- ---------------------------------------------------------------------------------------------------------------
SET NOCOUNT ON;
EXEC sys.sp_executesql N'
SELECT
    tomasCreadas                   = (SELECT COUNT(1) FROM dbo.TomaAsistencia) - ISNULL((SELECT tomasAntes FROM #culm001b2Mig16), 0),
    detallesAsignados              = ISNULL((SELECT detallesSinTomaAntes FROM #culm001b2Mig16), 0),
    detallesSinToma                = (SELECT COUNT(1) FROM dbo.DetalleAsistencia WHERE toma IS NULL),
    detallesIncoherentes           = (SELECT COUNT(1) FROM dbo.DetalleAsistencia da INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa
                                      WHERE da.asistio <> IIF(rc.codigo = N''AN'', 1, 0)),
    sesionesConCabeceraSinDetalle  = (SELECT COUNT(DISTINCT a.sesion) FROM dbo.Asistencia a
                                      WHERE NOT EXISTS (SELECT 1 FROM dbo.DetalleAsistencia da WHERE da.asistencia = a.id)
                                        AND NOT EXISTS (SELECT 1 FROM dbo.TomaAsistencia t WHERE t.sesion = a.sesion)),
    siguienteCodigoSecuencia       = (SELECT CAST(current_value AS BIGINT) FROM sys.sequences WHERE object_id = OBJECT_ID(N''dbo.seq_detalle_asistencia_codigo'')),
    maxCodigoDetalle               = (SELECT MAX(codigo) FROM dbo.DetalleAsistencia);';
DROP TABLE #culm001b2Mig16;
GO

-- ---------------------------------------------------------------------------------------------------------------
-- 5. Funciones de horas y vistas de B.2
-- ---------------------------------------------------------------------------------------------------------------
-- schema/functions/ufn_horas_sesion.sql
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.4, DEC-012): horas de una sesion = minutos entre inicio y fin / 60. 0 si alguna fecha es NULL o
-- si el fin no es posterior al inicio. Determinista, sin acceso a datos (inlineable).
CREATE OR ALTER FUNCTION [dbo].[ufn_horas_sesion]
(
    @fechaHoraInicio DATETIME2,
    @fechaHoraFin    DATETIME2
)
RETURNS DECIMAL(12,6)
WITH SCHEMABINDING
AS
BEGIN
    RETURN CAST(CASE
                    WHEN @fechaHoraInicio IS NULL OR @fechaHoraFin IS NULL OR @fechaHoraFin <= @fechaHoraInicio THEN 0
                    ELSE CAST(DATEDIFF(MINUTE, @fechaHoraInicio, @fechaHoraFin) AS DECIMAL(12,6)) / 60
                END AS DECIMAL(12,6));
END;
GO

-- schema/functions/ufn_horas_toma.sql
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.4, DEC-012): horas que vale cada toma de una sesion = horas de la sesion / numero de tomas de la
-- sesion. 0 si la sesion no existe, no tiene tomas o esta cancelada (dbo.SesionCancelacion). Solo para SP: las vistas usan
-- la ventana COUNT(*) OVER (PARTITION BY sesion).
CREATE OR ALTER FUNCTION [dbo].[ufn_horas_toma]
(
    @idSesion UNIQUEIDENTIFIER
)
RETURNS DECIMAL(12,6)
AS
BEGIN
    DECLARE @horas DECIMAL(12,6) = 0;
    DECLARE @tomas INT = (SELECT COUNT(1) FROM dbo.TomaAsistencia t WHERE t.sesion = @idSesion);

    IF @tomas > 0 AND NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = @idSesion)
        SELECT @horas = CAST(dbo.ufn_horas_sesion(s.fechaHoraInicio, s.fechaHoraFin) / @tomas AS DECIMAL(12,6))
        FROM dbo.Sesion s
        WHERE s.id = @idSesion;

    RETURN @horas;
END;
GO

-- schema/functions/ufn_calcular_porcentaje_inasistencia_horas.sql
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.4, DEC-012, DEC-024): porcentaje de inasistencia por horas = 100 * horasFalta / horasDictadas,
-- acotado a [0, 100]. 0 si horasDictadas es NULL o <= 0. Determinista, sin acceso a datos.
CREATE OR ALTER FUNCTION [dbo].[ufn_calcular_porcentaje_inasistencia_horas]
(
    @horasFalta    DECIMAL(12,6),
    @horasDictadas DECIMAL(12,6)
)
RETURNS DECIMAL(5,2)
WITH SCHEMABINDING
AS
BEGIN
    RETURN CAST(CASE
                    WHEN @horasDictadas IS NULL OR @horasDictadas <= 0 OR @horasFalta IS NULL OR @horasFalta <= 0 THEN 0
                    WHEN @horasFalta >= @horasDictadas THEN 100
                    ELSE ROUND(100.0 * @horasFalta / @horasDictadas, 2)
                END AS DECIMAL(5,2));
END;
GO

-- schema/views/uv_modo_toma_asistencia.sql
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.1): vista de catalogo (solo consulta, patron CAT-01) del modo de una toma de asistencia.
CREATE OR ALTER VIEW [dbo].[uv_modo_toma_asistencia]
AS
SELECT  id = m.id,
        codigo = m.codigo,
        nombre = m.nombre,
        usaCodigoQr = m.usaCodigoQr,
        marcaAusentesAlCerrar = m.marcaAusentesAlCerrar
FROM    dbo.ModoTomaAsistencia m;
GO

-- schema/views/uv_estado_toma_asistencia.sql
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.1): vista de catalogo (solo consulta, patron CAT-01) del estado de una toma de asistencia.
CREATE OR ALTER VIEW [dbo].[uv_estado_toma_asistencia]
AS
SELECT  id = e.id,
        codigo = e.codigo,
        nombre = e.nombre,
        estaAbierta = e.estaAbierta
FROM    dbo.EstadoTomaAsistencia e;
GO

-- schema/views/uv_toma_asistencia.sql
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.5): una fila por toma de asistencia con su modo, estado, ventana de la sesion y conteos.
--   horasSesion = ufn_horas_sesion(inicio, fin); totalTomasSesion = tomas de la sesion; horasToma = horasSesion /
--   totalTomasSesion (0 si la sesion esta cancelada). Conteos de la toma por RazonCausa (literales de catalogo cerrado,
--   [SUPUESTO-B-03]): totalPresentes AN, totalAusentes SJC, totalExcusas EX. tieneQrActivo = token sin fechaCierreUtc.
CREATE OR ALTER VIEW [dbo].[uv_toma_asistencia]
AS
SELECT  idToma = t.id,
        idSesion = t.sesion,
        idGrupo = s.grupo,
        numero = t.numero,
        idModo = m.id,
        codigoModo = m.codigo,
        nombreModo = m.nombre,
        usaCodigoQr = m.usaCodigoQr,
        marcaAusentesAlCerrar = m.marcaAusentesAlCerrar,
        idEstado = e.id,
        codigoEstado = e.codigo,
        nombreEstado = e.nombre,
        estaAbierta = e.estaAbierta,
        esImplicita = t.esImplicita,
        idDocenteApertura = t.docenteApertura,
        fechaAperturaUtc = t.fechaAperturaUtc,
        fechaCierreUtc = t.fechaCierreUtc,
        totalAusentesMarcados = t.totalAusentesMarcados,
        fechaHoraInicioSesion = s.fechaHoraInicio,
        fechaHoraFinSesion = s.fechaHoraFin,
        estaSesionCancelada = CAST(IIF(sc.sesion IS NULL, 0, 1) AS BIT),
        horasSesion = h.horasSesion,
        totalTomasSesion = n.totalTomas,
        horasToma = CAST(IIF(sc.sesion IS NULL AND n.totalTomas > 0, h.horasSesion / n.totalTomas, 0) AS DECIMAL(12,6)),
        totalRegistros = ISNULL(d.totalRegistros, 0),
        totalPresentes = ISNULL(d.totalPresentes, 0),
        totalAusentes = ISNULL(d.totalAusentes, 0),
        totalExcusas = ISNULL(d.totalExcusas, 0),
        tieneQrActivo = CAST(IIF(EXISTS (SELECT 1 FROM dbo.TokenAsistenciaToma tk WHERE tk.toma = t.id AND tk.fechaCierreUtc IS NULL), 1, 0) AS BIT)
FROM    dbo.TomaAsistencia t
INNER JOIN dbo.Sesion s
ON      s.id = t.sesion
INNER JOIN dbo.ModoTomaAsistencia m
ON      m.id = t.modo
INNER JOIN dbo.EstadoTomaAsistencia e
ON      e.id = t.estado
LEFT JOIN dbo.SesionCancelacion sc
ON      sc.sesion = t.sesion
CROSS APPLY (SELECT horasSesion = dbo.ufn_horas_sesion(s.fechaHoraInicio, s.fechaHoraFin)) h
CROSS APPLY (SELECT totalTomas = COUNT(1) FROM dbo.TomaAsistencia t2 WHERE t2.sesion = t.sesion) n
OUTER APPLY (
        SELECT  totalRegistros = COUNT(1),
                totalPresentes = SUM(IIF(rc.codigo = N'AN', 1, 0)),
                totalAusentes = SUM(IIF(rc.codigo = N'SJC', 1, 0)),
                totalExcusas = SUM(IIF(rc.codigo = N'EX', 1, 0))
        FROM    dbo.DetalleAsistencia da
        INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa
        WHERE   da.toma = t.id
) d;
GO

-- schema/views/uv_token_asistencia_toma.sql
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.5, DEC-015): estado del token/PIN de asistencia de cada toma. Nunca expone tokenHash.
--   estaActivo      = fechaCierreUtc IS NULL
--   estaVigente     = activo y SYSUTCDATETIME() < fechaExpiracionUtc
--   debeRotar       = vigente y SYSUTCDATETIME() >= fechaRotacionUtc + ASISTENCIA_QR/ROTACION_SEGUNDOS
--   anteriorVigente = vigente, pinAnterior NOT NULL y SYSUTCDATETIME() < fechaRotacionUtc + ASISTENCIA_QR/TOLERANCIA_SEGUNDOS
--   totalRegistrosQr = detalles de la toma registrados por el estudiante
CREATE OR ALTER VIEW [dbo].[uv_token_asistencia_toma]
AS
SELECT  id = tk.id,
        idToma = tk.toma,
        idSesion = t.sesion,
        idGrupo = s.grupo,
        idDocenteEmisor = tk.docenteEmisor,
        pin = tk.pin,
        pinAnterior = tk.pinAnterior,
        fechaEmisionUtc = tk.fechaEmisionUtc,
        fechaRotacionUtc = tk.fechaRotacionUtc,
        fechaExpiracionUtc = tk.fechaExpiracionUtc,
        fechaCierreUtc = tk.fechaCierreUtc,
        estaActivo = CAST(IIF(tk.fechaCierreUtc IS NULL, 1, 0) AS BIT),
        estaVigente = CAST(IIF(tk.fechaCierreUtc IS NULL AND SYSUTCDATETIME() < tk.fechaExpiracionUtc, 1, 0) AS BIT),
        debeRotar = CAST(IIF(tk.fechaCierreUtc IS NULL AND SYSUTCDATETIME() < tk.fechaExpiracionUtc
                             AND SYSUTCDATETIME() >= DATEADD(SECOND, p.rotacionSegundos, tk.fechaRotacionUtc), 1, 0) AS BIT),
        anteriorVigente = CAST(IIF(tk.fechaCierreUtc IS NULL AND SYSUTCDATETIME() < tk.fechaExpiracionUtc AND tk.pinAnterior IS NOT NULL
                                   AND SYSUTCDATETIME() < DATEADD(SECOND, p.toleranciaSegundos, tk.fechaRotacionUtc), 1, 0) AS BIT),
        totalRegistrosQr = (SELECT COUNT(1) FROM dbo.DetalleAsistencia da WHERE da.toma = tk.toma AND da.registradoPorEstudiante = 1),
        nombreAsignatura = g.nombreAsignatura,
        nombreGrupo = g.nombre,
        numeroSesion = s.numero,
        numeroToma = t.numero
FROM    dbo.TokenAsistenciaToma tk
INNER JOIN dbo.TomaAsistencia t
ON      t.id = tk.toma
INNER JOIN dbo.Sesion s
ON      s.id = t.sesion
INNER JOIN dbo.uv_grupo g
ON      g.id = s.grupo
CROSS APPLY (
        SELECT  rotacionSegundos = IIF(r.valor IS NULL OR r.valor < 1, 60, r.valor),
                toleranciaSegundos = IIF(o.valor IS NULL OR o.valor < 0, 0, o.valor)
        FROM    (SELECT valor = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA_QR', 'ROTACION_SEGUNDOS')) r
        CROSS JOIN (SELECT valor = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA_QR', 'TOLERANCIA_SEGUNDOS')) o
) p;
GO

-- schema/views/uv_detalle_asistencia_v2.sql
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.5, DEC-011, DEC-012): detalle de asistencia por toma. Mismas columnas de uv_detalle_asistencia
-- (congelada, intacta) + la toma, la sesion, la matricula, el modo, las horas que vale la toma (0 si la sesion esta
-- cancelada), quien registro (registradoPorEstudiante) y cuando (fechaRegistroUtc).
CREATE OR ALTER VIEW [dbo].[uv_detalle_asistencia_v2]
AS
SELECT  id = da.id,
        codigo = da.codigo,
        idAsistencia = a.id,
        asistio = da.asistio,
        idRazonCausa = rc.id,
        nombreRazonCausa = rc.nombre,
        codigoRazonCausa = rc.codigo,
        fechaHoraInicio = da.fechaHoraInicio,
        fechaHoraFin = da.fechaHoraFin,
        idToma = t.id,
        numeroToma = t.numero,
        idSesion = a.sesion,
        idEstudianteGrupo = a.estudianteGrupo,
        idModoToma = m.id,
        codigoModoToma = m.codigo,
        horasToma = CAST(IIF(sc.sesion IS NULL AND n.totalTomas > 0, dbo.ufn_horas_sesion(s.fechaHoraInicio, s.fechaHoraFin) / n.totalTomas, 0) AS DECIMAL(12,6)),
        registradoPorEstudiante = da.registradoPorEstudiante,
        fechaRegistroUtc = da.fechaRegistroUtc,
        estaSesionCancelada = CAST(IIF(sc.sesion IS NULL, 0, 1) AS BIT)
FROM    dbo.DetalleAsistencia da
INNER JOIN dbo.Asistencia a
ON      a.id = da.asistencia
INNER JOIN dbo.uv_razon_causa rc
ON      rc.id = da.razonCausa
INNER JOIN dbo.TomaAsistencia t
ON      t.id = da.toma
INNER JOIN dbo.ModoTomaAsistencia m
ON      m.id = t.modo
INNER JOIN dbo.Sesion s
ON      s.id = a.sesion
LEFT JOIN dbo.SesionCancelacion sc
ON      sc.sesion = a.sesion
CROSS APPLY (SELECT totalTomas = COUNT(1) FROM dbo.TomaAsistencia t2 WHERE t2.sesion = t.sesion) n;
GO

-- schema/views/uv_asistencia_sesion_horas.sql
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.5, DEC-012, DEC-024, [SUPUESTO-B-15], NB-9): una fila por cabecera Asistencia con las horas de la
-- sesion repartidas por toma y el estado consolidado de la sesion.
--   horasSesion = ufn_horas_sesion(inicio, fin); cada toma vale horasSesion / totalTomasSesion (0 si la sesion esta cancelada)
--   horasAsistidas (AN), horasFalta (asistio = 0 y SJC), horasExcusa (EX); horasSinRegistro = horasSesion - las tres
--   (se calcula por conteo de tomas para no acumular redondeos; sin tomas o cancelada = horasSesion).
--   codigoRazonCausaConsolidado: SJC si alguna toma es SJC; si no EX si alguna es EX; si no AN si alguna es AN; si no NULL.
--   esParcial = mezcla AN y SJC. Literales de RazonCausa de catalogo cerrado ([SUPUESTO-B-03]).
CREATE OR ALTER VIEW [dbo].[uv_asistencia_sesion_horas]
AS
SELECT  idAsistencia = a.id,
        idEstudianteGrupo = a.estudianteGrupo,
        idSesion = a.sesion,
        idGrupo = s.grupo,
        totalTomasSesion = n.totalTomas,
        tomasConRegistro = ISNULL(d.conRegistro, 0),
        horasSesion = h.horasSesion,
        horasAsistidas = CAST(IIF(x.reparte = 1, h.horasSesion * ISNULL(d.nAN, 0) / n.totalTomas, 0) AS DECIMAL(12,6)),
        horasFalta = CAST(IIF(x.reparte = 1, h.horasSesion * ISNULL(d.nFalta, 0) / n.totalTomas, 0) AS DECIMAL(12,6)),
        horasExcusa = CAST(IIF(x.reparte = 1, h.horasSesion * ISNULL(d.nEX, 0) / n.totalTomas, 0) AS DECIMAL(12,6)),
        horasSinRegistro = CAST(IIF(x.reparte = 1,
                                    h.horasSesion * (n.totalTomas - ISNULL(d.nAN, 0) - ISNULL(d.nFalta, 0) - ISNULL(d.nEX, 0)) / n.totalTomas,
                                    h.horasSesion) AS DECIMAL(12,6)),
        codigoRazonCausaConsolidado = CAST(CASE WHEN ISNULL(d.nSJC, 0) > 0 THEN N'SJC'
                                                WHEN ISNULL(d.nEX, 0) > 0 THEN N'EX'
                                                WHEN ISNULL(d.nAN, 0) > 0 THEN N'AN'
                                           END AS NVARCHAR(10)),
        esParcial = CAST(IIF(ISNULL(d.nAN, 0) > 0 AND ISNULL(d.nSJC, 0) > 0, 1, 0) AS BIT),
        tieneFaltaSinJustaCausa = CAST(IIF(ISNULL(d.nFalta, 0) > 0, 1, 0) AS BIT)
FROM    dbo.Asistencia a
INNER JOIN dbo.Sesion s
ON      s.id = a.sesion
CROSS APPLY (SELECT horasSesion = dbo.ufn_horas_sesion(s.fechaHoraInicio, s.fechaHoraFin)) h
CROSS APPLY (SELECT totalTomas = COUNT(1) FROM dbo.TomaAsistencia t WHERE t.sesion = a.sesion) n
CROSS APPLY (SELECT reparte = CAST(IIF(n.totalTomas > 0 AND NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = a.sesion), 1, 0) AS BIT)) x
OUTER APPLY (
        SELECT  conRegistro = COUNT(1),
                nAN = SUM(IIF(rc.codigo = N'AN', 1, 0)),
                nFalta = SUM(IIF(rc.codigo = N'SJC' AND da.asistio = 0, 1, 0)),
                nSJC = SUM(IIF(rc.codigo = N'SJC', 1, 0)),
                nEX = SUM(IIF(rc.codigo = N'EX', 1, 0))
        FROM    dbo.DetalleAsistencia da
        INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa
        WHERE   da.asistencia = a.id
) d;
GO

-- schema/views/uv_faltantes_toma.sql
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.5, HU175, DEC-013): faltantes de una toma = matriculas ACTIVAS (codigoEstadoEstudiante = A) del
-- grupo sin presencia en la toma: sin detalle (tieneRegistro = 0) o con SJC. Excluye a quien tiene AN o EX en la toma.
--   fueMarcadoAlCerrar = 1 si el SJC lo inserto el cierre de la toma (usp_cerrar_toma_asistencia / usp_cerrar_tomas_vencidas
--   registran el SJC con fechaRegistroUtc = fechaCierreUtc de la toma y registradoPorEstudiante = 0); si el docente lo
--   corrige despues, deja de serlo.
CREATE OR ALTER VIEW [dbo].[uv_faltantes_toma]
AS
SELECT  idToma = t.id,
        idSesion = t.sesion,
        idGrupo = s.grupo,
        numeroToma = t.numero,
        idEstudianteGrupo = eg.id,
        idEstudiante = eg.idEstudiante,
        nombreCompletoEstudiante = eg.nombreCompletoEstudiante,
        tieneRegistro = CAST(IIF(d.id IS NULL, 0, 1) AS BIT),
        idDetalleAsistencia = d.id,
        codigoRazonCausa = rc.codigo,
        fueMarcadoAlCerrar = CAST(IIF(d.id IS NOT NULL AND rc.codigo = N'SJC' AND d.registradoPorEstudiante = 0
                                      AND t.fechaCierreUtc IS NOT NULL AND d.fechaRegistroUtc = t.fechaCierreUtc, 1, 0) AS BIT)
FROM    dbo.TomaAsistencia t
INNER JOIN dbo.Sesion s
ON      s.id = t.sesion
INNER JOIN dbo.uv_estudiante_grupo eg
ON      eg.idGrupo = s.grupo
AND     eg.codigoEstadoEstudiante = N'A'
OUTER APPLY (
        SELECT  TOP 1 da.id, da.razonCausa, da.registradoPorEstudiante, da.fechaRegistroUtc
        FROM    dbo.Asistencia a
        INNER JOIN dbo.DetalleAsistencia da ON da.asistencia = a.id AND da.toma = t.id
        WHERE   a.estudianteGrupo = eg.id AND a.sesion = t.sesion
) d
LEFT JOIN dbo.RazonCausa rc
ON      rc.id = d.razonCausa
WHERE   d.id IS NULL OR rc.codigo NOT IN (N'AN', N'EX');
GO

-- schema/views/uv_sesion_estado.sql
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.1 (CONTRACT §2.5): una fila por sesion (sobre uv_sesion_v2, que no se modifica) con su estado de
-- cancelacion (dbo.SesionCancelacion, LEFT) y la ventana de registro con tolerancia:
--   ventanaAperturaUtc = inicio - ASISTENCIA/TOLERANCIA_MINUTOS (NULL si la procedencia temporal es INDETERMINADA)
--   ventanaCierreUtc   = fin + ASISTENCIA/MARGEN_RETARDO_MINUTOS
--   ventanaAbierta     = no cancelada, procedencia confirmada y apertura <= SYSUTCDATETIME() < cierre
-- Los dos parametros se leen una sola vez (CROSS APPLY); un parametro ausente o negativo vale 0 (regla estricta).
-- horasSesion = minutos de la sesion / 60 (0 si fin <= inicio).
-- CULM-001 B.2 (CONTRACT §2.5): totalTomas (tomas de la sesion), tieneTomaAbierta e idTomaAbierta (la toma sin fechaCierreUtc).
CREATE OR ALTER VIEW [dbo].[uv_sesion_estado]
AS
SELECT  idSesion = s.id,
        idGrupo = s.idGrupo,
        numero = s.numero,
        nombre = s.nombre,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin,
        procedenciaTemporal = s.procedenciaTemporal,
        estaCancelada = CAST(IIF(sc.sesion IS NULL, 0, 1) AS BIT),
        idTipoCancelacion = tc.id,
        codigoTipoCancelacion = tc.codigo,
        nombreTipoCancelacion = tc.nombre,
        esCancelacionAutomatica = tc.esAutomatica,
        motivoCancelacion = sc.motivo,
        idDiaFestivo = sc.diaFestivo,
        nombreDiaFestivo = df.nombre,
        fechaCancelacionUtc = sc.fechaCancelacionUtc,
        idUsuarioCancelacion = sc.usuarioEjecutor,
        ventanaAperturaUtc = IIF(s.procedenciaTemporal IS NULL, NULL, DATEADD(MINUTE, -p.toleranciaMinutos, s.fechaHoraInicio)),
        ventanaCierreUtc = DATEADD(MINUTE, p.margenMinutos, s.fechaHoraFin),
        ventanaAbierta = CAST(IIF(sc.sesion IS NULL
                                  AND s.procedenciaTemporal IS NOT NULL
                                  AND DATEADD(MINUTE, -p.toleranciaMinutos, s.fechaHoraInicio) <= SYSUTCDATETIME()
                                  AND SYSUTCDATETIME() < DATEADD(MINUTE, p.margenMinutos, s.fechaHoraFin), 1, 0) AS BIT),
        horasSesion = CAST(IIF(s.fechaHoraFin > s.fechaHoraInicio,
                               CAST(DATEDIFF(MINUTE, s.fechaHoraInicio, s.fechaHoraFin) AS DECIMAL(12,6)) / 60, 0) AS DECIMAL(12,6)),
        totalTomas = tm.totalTomas,
        tieneTomaAbierta = CAST(IIF(tm.idTomaAbierta IS NULL, 0, 1) AS BIT),
        idTomaAbierta = tm.idTomaAbierta
FROM    dbo.uv_sesion_v2 s
CROSS APPLY (
        SELECT  toleranciaMinutos = IIF(t.valor IS NULL OR t.valor < 0, 0, t.valor),
                margenMinutos = IIF(m.valor IS NULL OR m.valor < 0, 0, m.valor)
        FROM    (SELECT valor = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'TOLERANCIA_MINUTOS')) t
        CROSS JOIN (SELECT valor = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS')) m
) p
LEFT JOIN dbo.SesionCancelacion sc
ON      sc.sesion = s.id
LEFT JOIN dbo.uv_tipo_cancelacion_sesion tc
ON      tc.id = sc.tipoCancelacion
LEFT JOIN dbo.DiaFestivo df
ON      df.id = sc.diaFestivo
OUTER APPLY (
        SELECT  totalTomas = COUNT(1),
                idTomaAbierta = MAX(IIF(t.fechaCierreUtc IS NULL, CAST(t.id AS NVARCHAR(36)), NULL))
        FROM    dbo.TomaAsistencia t
        WHERE   t.sesion = s.id
) tm0
CROSS APPLY (SELECT totalTomas = ISNULL(tm0.totalTomas, 0), idTomaAbierta = CAST(tm0.idTomaAbierta AS UNIQUEIDENTIFIER)) tm;
GO

-- schema/views/uv_cumplimiento_sesion_grupo.sql
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU065: una fila por sesion con su estado de cumplimiento (D4, D7). Consume uv_sesion_v2 (procedencia temporal) y
-- uv_grupo_programa; no altera las vistas congeladas.
-- CULM-001 B.1 (CONTRACT §2.6): una sesion cancelada (dbo.SesionCancelacion, por el docente o por festivo) sale de la
-- vista y con ello de sesionesProgramadas, vencidas, ejecutadas, cumplimiento, progreso de calendario y tendencia.
-- Columnas sin cambio.
-- CULM-001 B.2 (CONTRACT §2.6, [SUPUESTO-B-06]): tieneRegistroAsistencia = existe Asistencia O existe TomaAsistencia (una toma
-- QR abierta y cerrada sin lecturas cuenta como sesion ejecutada); columnas nuevas totalTomas y horasSesion.
CREATE OR ALTER VIEW [dbo].[uv_cumplimiento_sesion_grupo]
AS
SELECT  idSesion = s.id,
        idGrupo = s.idGrupo,
        idPeriodoAcademico = gp.idPeriodoAcademico,
        idPrograma = gp.idPrograma,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin,
        estaVencida = CAST(IIF(s.procedenciaTemporal IS NOT NULL AND s.fechaHoraFin <= SYSUTCDATETIME(), 1, 0) AS BIT),
        procedenciaIndeterminada = CAST(IIF(s.procedenciaTemporal IS NULL, 1, 0) AS BIT),
        tieneRegistroAsistencia = CAST(IIF(EXISTS (SELECT 1 FROM dbo.uv_asistencia a WHERE a.idSesion = s.id)
                                           OR EXISTS (SELECT 1 FROM dbo.TomaAsistencia t WHERE t.sesion = s.id), 1, 0) AS BIT),
        totalTomas = (SELECT COUNT(1) FROM dbo.TomaAsistencia t WHERE t.sesion = s.id),
        horasSesion = dbo.ufn_horas_sesion(s.fechaHoraInicio, s.fechaHoraFin)
FROM    dbo.uv_sesion_v2 s
INNER JOIN dbo.uv_grupo_programa gp
ON      gp.idGrupo = s.idGrupo
WHERE   NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = s.id)
GO

-- schema/views/uv_resumen_asistencia_estudiante_grupo.sql
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU066/HU067/HU069/HU070: una fila por matricula (EstudianteGrupo) con sus cifras de asistencia.
-- Denominador (D1): sesiones vencidas CON registro del grupo. Falta (D2): asistio = 0 con razon SJC; la excusa (EX) no cuenta.
-- CULM-001 B.2 (CONTRACT §2.6, §2.9, DEC-012, DEC-024, NB-2): inasistencia por HORAS conservando los nombres.
--   sesionesEjecutadas: sesiones vencidas, con registro (Asistencia o TomaAsistencia) y no canceladas (sin cambio de nombre).
--   asistencias / faltasSinJustaCausa / excusas: pasan a contar TOMAS (con una toma por sesion = sesiones, igual que antes).
--   tomasDictadas / horasDictadas: tomas y horas (ufn_horas_sesion) de esas mismas sesiones, sin mirar el estado de la toma.
--   horasAsistidas / horasFalta / horasExcusa: suma de uv_asistencia_sesion_horas en esas sesiones; horasSinRegistro =
--   horasDictadas - las tres (nunca negativo).
--   porcentajeInasistencia = ufn_calcular_porcentaje_inasistencia_horas(horasFalta, horasDictadas); codigoPermanencia sobre ese
--   porcentaje (ufn_clasificar_permanencia sin cambio). porcentajeInasistenciaSesiones = formula anterior por sesiones
--   (sesionesConFaltaSinJustaCausa / sesionesEjecutadas), solo trazabilidad. umbralAdvertencia / umbralPerdida: parametros.
--   sesionesAsistidas / sesionesConFaltaSinJustaCausa / sesionesConExcusa: sesiones por estado consolidado (consumidores
--   diferidos a D).
CREATE OR ALTER VIEW [dbo].[uv_resumen_asistencia_estudiante_grupo]
AS
SELECT  idEstudianteGrupo = eg.id,
        idEstudiante = eg.idEstudiante,
        idGrupo = eg.idGrupo,
        idAsignatura = g.idAsignatura,
        idPrograma = gp.idPrograma,
        idPeriodoAcademico = gp.idPeriodoAcademico,
        codigoEstadoEstudiante = eg.codigoEstadoEstudiante,
        sesionesEjecutadas = ISNULL(se.sesionesEjecutadas, 0),
        asistencias = ISNULL(de.asistencias, 0),
        faltasSinJustaCausa = ISNULL(de.faltas, 0),
        excusas = ISNULL(de.excusas, 0),
        porcentajeInasistencia = p.porcentaje,
        codigoPermanencia = dbo.ufn_clasificar_permanencia(p.porcentaje, eg.codigoEstadoEstudiante),
        tomasDictadas = ISNULL(se.tomasDictadas, 0),
        horasDictadas = hd.horasDictadas,
        horasAsistidas = hd.horasAsistidas,
        horasFalta = hd.horasFalta,
        horasExcusa = hd.horasExcusa,
        horasSinRegistro = hd.horasSinRegistro,
        porcentajeAsistenciaHoras = dbo.ufn_calcular_porcentaje_inasistencia_horas(hd.horasAsistidas, hd.horasDictadas),
        porcentajeExcusaHoras = dbo.ufn_calcular_porcentaje_inasistencia_horas(hd.horasExcusa, hd.horasDictadas),
        porcentajeSinRegistroHoras = dbo.ufn_calcular_porcentaje_inasistencia_horas(hd.horasSinRegistro, hd.horasDictadas),
        porcentajeInasistenciaSesiones = CAST(IIF(ISNULL(se.sesionesEjecutadas, 0) = 0, 0,
                                                  100.0 * ISNULL(hs.sesionesConFalta, 0) / se.sesionesEjecutadas) AS DECIMAL(5,2)),
        umbralAdvertencia = u.umbralAdvertencia,
        umbralPerdida = u.umbralPerdida,
        sesionesAsistidas = ISNULL(hs.sesionesAsistidas, 0),
        sesionesConFaltaSinJustaCausa = ISNULL(hs.sesionesConFalta, 0),
        sesionesConExcusa = ISNULL(hs.sesionesConExcusa, 0)
FROM    dbo.uv_estudiante_grupo eg
INNER JOIN dbo.uv_grupo g
ON      g.id = eg.idGrupo
INNER JOIN dbo.uv_grupo_programa gp
ON      gp.idGrupo = eg.idGrupo
LEFT JOIN (
            SELECT  c.idGrupo,
                    sesionesEjecutadas = COUNT(*),
                    tomasDictadas = SUM(c.totalTomas),
                    horasDictadas = SUM(c.horasSesion)
            FROM    dbo.uv_cumplimiento_sesion_grupo c
            WHERE   c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1
            GROUP BY c.idGrupo
          ) se
ON      se.idGrupo = eg.idGrupo
LEFT JOIN (
            SELECT  v.idEstudianteGrupo,
                    asistencias = SUM(IIF(v.asistio = 1, 1, 0)),
                    faltas = SUM(IIF(v.asistio = 0 AND v.codigoRazonCausa = N'SJC', 1, 0)),
                    excusas = SUM(IIF(v.codigoRazonCausa = N'EX', 1, 0))
            FROM    dbo.uv_detalle_asistencia_v2 v
            INNER JOIN dbo.uv_cumplimiento_sesion_grupo c ON c.idSesion = v.idSesion AND c.estaVencida = 1
            GROUP BY v.idEstudianteGrupo
          ) de
ON      de.idEstudianteGrupo = eg.id
LEFT JOIN (
            SELECT  h.idEstudianteGrupo,
                    horasAsistidas = SUM(h.horasAsistidas),
                    horasFalta = SUM(h.horasFalta),
                    horasExcusa = SUM(h.horasExcusa),
                    sesionesAsistidas = SUM(IIF(h.codigoRazonCausaConsolidado = N'AN', 1, 0)),
                    sesionesConFalta = SUM(IIF(h.tieneFaltaSinJustaCausa = 1, 1, 0)),
                    sesionesConExcusa = SUM(IIF(h.codigoRazonCausaConsolidado = N'EX', 1, 0))
            FROM    dbo.uv_asistencia_sesion_horas h
            INNER JOIN dbo.uv_cumplimiento_sesion_grupo c ON c.idSesion = h.idSesion AND c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1
            GROUP BY h.idEstudianteGrupo
          ) hs
ON      hs.idEstudianteGrupo = eg.id
CROSS APPLY (
            SELECT  horasDictadas = CAST(ISNULL(se.horasDictadas, 0) AS DECIMAL(12,6)),
                    horasAsistidas = CAST(ISNULL(hs.horasAsistidas, 0) AS DECIMAL(12,6)),
                    horasFalta = CAST(ISNULL(hs.horasFalta, 0) AS DECIMAL(12,6)),
                    horasExcusa = CAST(ISNULL(hs.horasExcusa, 0) AS DECIMAL(12,6)),
                    horasSinRegistro = CAST(IIF(ISNULL(se.horasDictadas, 0) - ISNULL(hs.horasAsistidas, 0) - ISNULL(hs.horasFalta, 0) - ISNULL(hs.horasExcusa, 0) < 0, 0,
                                                ISNULL(se.horasDictadas, 0) - ISNULL(hs.horasAsistidas, 0) - ISNULL(hs.horasFalta, 0) - ISNULL(hs.horasExcusa, 0)) AS DECIMAL(12,6))
          ) hd
CROSS APPLY (SELECT porcentaje = dbo.ufn_calcular_porcentaje_inasistencia_horas(hd.horasFalta, hd.horasDictadas)) p
CROSS APPLY (
            SELECT  umbralAdvertencia = TRY_CAST(NULLIF(TRIM(CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_ADVERTENCIA') AS NVARCHAR(20))), '') AS DECIMAL(5,2)),
                    umbralPerdida = TRY_CAST(NULLIF(TRIM(CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_PERDIDA') AS NVARCHAR(20))), '') AS DECIMAL(5,2))
          ) u;
GO

-- GRANT SELECT de las vistas nuevas al rol de runtime (el bucle uv_* de rol_asistencias_runtime.sql corre en deploy_schema.ps1)
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NOT NULL
BEGIN
    IF OBJECT_ID(N'dbo.uv_modo_toma_asistencia', N'V') IS NOT NULL GRANT SELECT ON [dbo].[uv_modo_toma_asistencia] TO [rol_asistencias_runtime];
    IF OBJECT_ID(N'dbo.uv_estado_toma_asistencia', N'V') IS NOT NULL GRANT SELECT ON [dbo].[uv_estado_toma_asistencia] TO [rol_asistencias_runtime];
    IF OBJECT_ID(N'dbo.uv_toma_asistencia', N'V') IS NOT NULL GRANT SELECT ON [dbo].[uv_toma_asistencia] TO [rol_asistencias_runtime];
    IF OBJECT_ID(N'dbo.uv_token_asistencia_toma', N'V') IS NOT NULL GRANT SELECT ON [dbo].[uv_token_asistencia_toma] TO [rol_asistencias_runtime];
    IF OBJECT_ID(N'dbo.uv_detalle_asistencia_v2', N'V') IS NOT NULL GRANT SELECT ON [dbo].[uv_detalle_asistencia_v2] TO [rol_asistencias_runtime];
    IF OBJECT_ID(N'dbo.uv_asistencia_sesion_horas', N'V') IS NOT NULL GRANT SELECT ON [dbo].[uv_asistencia_sesion_horas] TO [rol_asistencias_runtime];
    IF OBJECT_ID(N'dbo.uv_faltantes_toma', N'V') IS NOT NULL GRANT SELECT ON [dbo].[uv_faltantes_toma] TO [rol_asistencias_runtime];
END
GO
