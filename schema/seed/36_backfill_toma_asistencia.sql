USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.3 (b), §2.14 paso 3, B-1 de REVIEW-1): conversion de DetalleAsistencia.toma a NOT NULL.
-- Se ejecuta en cada deploy_schema.ps1 despues de los catalogos 35 y es identica al paso 3 de la migracion 16. Solo actua si
-- toma todavia admite NULL; en una transaccion con XACT_ABORT ON y en este orden exacto:
--   1. aborta (THROW 50010) si una asistencia tiene mas de un detalle (no deberia: lo impide UX_DetalleAsistencia_Asistencia);
--   2. backfill: toma 1 implicita (MANUAL, CERRADA, docente del grupo, apertura = inicio, cierre = fin) por cada sesion con
--      detalles sin toma y UPDATE de DetalleAsistencia.toma (las sesiones sin detalle no reciben toma, NB-9);
--   3. borra los dependientes de toma si existen (FK, UX e IX);
--   4. ALTER COLUMN toma NOT NULL;
--   5. borra el indice antiguo UX_DetalleAsistencia_Asistencia;
--   6. recrea UX_DetalleAsistencia_Asistencia_Toma, IX_DetalleAsistencia_Toma y FK_DetalleAsistencia_TomaAsistencia.
-- Despues (siempre) realinea la secuencia de codigo si quedo por detras de MAX(codigo) (B2-MIG-06). Un segundo despliegue no
-- cambia nada (B2-MIG-05).
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
