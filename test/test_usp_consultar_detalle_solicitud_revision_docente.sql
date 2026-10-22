USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
-- El indice unico filtrado de ArchivoSoporte exige QUOTED_IDENTIFIER ON para todo DML directo (sqlcmd lo deja OFF).
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- HU035/HU036: pruebas de usp_consultar_detalle_solicitud_revision_docente (DB-01..DB-08 del TEST_PLAN).
-- Los fixtures corren dentro de UNA transaccion con ROLLBACK final (sin datos persistentes).
-- Los casos de parametros nulos (THROW 51000) corren FUERA de la transaccion: el SP usa XACT_ABORT ON y el
-- THROW condenaria cualquier transaccion abierta (solo lectura, no hay datos que proteger).
-- DB-07: CK_ArchivoSoporte_EstadoVinculo impide vincular a una solicitud un archivo que no este ATTACHED,
-- por lo que el estado distinto se simula cambiando (dentro de la transaccion) el parametro ARCHIVO.ESTADO_ADJUNTO.
-- ============================================================================
IF OBJECT_ID('tempdb..#hu35_expect') IS NOT NULL DROP PROCEDURE #hu35_expect;
GO
CREATE PROCEDURE #hu35_expect @label VARCHAR(100), @ok BIT
AS
BEGIN
    IF @ok IS NULL OR @ok <> 1
    BEGIN
        DECLARE @mensaje NVARCHAR(400) = CONCAT('TEST FAILED: HU035_HU036_', @label);
        THROW 52300, @mensaje, 1;
    END
END;
GO

DECLARE @group UNIQUEIDENTIFIER, @teacher UNIQUEIDENTIFIER, @teacher2 UNIQUEIDENTIFIER;
DECLARE @studentA UNIQUEIDENTIFIER, @studentB UNIQUEIDENTIFIER, @egA UNIQUEIDENTIFIER, @egB UNIQUEIDENTIFIER;
DECLARE @userA UNIQUEIDENTIFIER, @userT UNIQUEIDENTIFIER, @userT2 UNIQUEIDENTIFIER, @userCoord UNIQUEIDENTIFIER;
DECLARE @reasonSjc UNIQUEIDENTIFIER, @estadoP UNIQUEIDENTIFIER;

SELECT TOP 1 @group = g.id, @teacher = g.docente
FROM dbo.Grupo g
WHERE (SELECT COUNT(*) FROM dbo.uv_estudiante_grupo x WHERE x.idGrupo = g.id AND x.codigoEstadoEstudiante = 'A') >= 2
ORDER BY (SELECT COUNT(*) FROM dbo.uv_estudiante_grupo x WHERE x.idGrupo = g.id) ASC, g.id;

SELECT @studentA = z.idEstudiante, @egA = z.id FROM (
    SELECT idEstudiante, id, ROW_NUMBER() OVER (ORDER BY idEstudiante) rn
    FROM dbo.uv_estudiante_grupo WHERE idGrupo = @group AND codigoEstadoEstudiante = 'A') z WHERE z.rn = 1;
SELECT @studentB = z.idEstudiante, @egB = z.id FROM (
    SELECT idEstudiante, id, ROW_NUMBER() OVER (ORDER BY idEstudiante) rn
    FROM dbo.uv_estudiante_grupo WHERE idGrupo = @group AND codigoEstadoEstudiante = 'A') z WHERE z.rn = 2;

SELECT TOP 1 @teacher2 = d.id FROM dbo.Docente d WHERE d.id <> @teacher ORDER BY d.id;
SELECT @userA = usuario FROM dbo.Estudiante WHERE id = @studentA;
SELECT @userT = usuario FROM dbo.Docente WHERE id = @teacher;
SELECT @userT2 = usuario FROM dbo.Docente WHERE id = @teacher2;
SELECT TOP 1 @userCoord = usuario FROM dbo.Coordinador ORDER BY id;
SELECT @reasonSjc = id FROM dbo.RazonCausa WHERE codigo = 'SJC';
SELECT @estadoP = id FROM dbo.Estado WHERE codigo = 'P';

IF @group IS NULL OR @teacher IS NULL OR @teacher2 IS NULL OR @studentA IS NULL OR @studentB IS NULL
   OR @egA IS NULL OR @egB IS NULL OR @userA IS NULL OR @userT IS NULL OR @userT2 IS NULL OR @userCoord IS NULL
   OR @reasonSjc IS NULL OR @estadoP IS NULL
    THROW 52301, 'TEST FAILED: HU035_HU036 fixture missing (seed data).', 1;

DECLARE @session UNIQUEIDENTIFIER = NEWID(), @asisA UNIQUEIDENTIFIER = NEWID(), @asisB UNIQUEIDENTIFIER = NEWID();
DECLARE @detalleA UNIQUEIDENTIFIER = NEWID();
DECLARE @number INT = 1 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @group);
DECLARE @sessionCode NVARCHAR(50) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8);
DECLARE @detalleCode INT = 1 + (SELECT ISNULL(MAX(codigo), 0) FROM dbo.DetalleAsistencia);
DECLARE @inicioSesion DATETIME2(7) = '2026-10-19T15:30:45.1234567';
DECLARE @reqA UNIQUEIDENTIFIER = NEWID(), @reqB UNIQUEIDENTIFIER = NEWID(), @file UNIQUEIDENTIFIER = NEWID();
DECLARE @sha CHAR(64) = LOWER(CONVERT(CHAR(64), HASHBYTES('SHA2_256', 'hu035-1'), 2));
DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @corrAdj UNIQUEIDENTIFIER = NEWID();
DECLARE @ok BIT, @rows INT, @cols NVARCHAR(MAX);

CREATE TABLE #r (idSolicitudRevisionAsistencia UNIQUEIDENTIFIER, nombreSolicitud NVARCHAR(50), fechaSolicitud DATE,
    codigoEstado NVARCHAR(5), nombreEstado NVARCHAR(100), justificacionSolicitud NVARCHAR(MAX), justificacionRespuesta NVARCHAR(MAX),
    idEstudiante UNIQUEIDENTIFIER, nombreEstudiante NVARCHAR(400), idSesion UNIQUEIDENTIFIER, numeroSesion INT,
    fechaHoraInicioSesion DATETIME2(7), procedenciaTemporalSesion NVARCHAR(24), idGrupo UNIQUEIDENTIFIER, codigoGrupo INT,
    nombreGrupo NVARCHAR(100), idAsignatura UNIQUEIDENTIFIER, codigoAsignatura NVARCHAR(100), nombreAsignatura NVARCHAR(100),
    asistio BIT, codigoRazonCausa NVARCHAR(5), nombreRazonCausa NVARCHAR(50),
    idArchivoSoporte UNIQUEIDENTIFIER, nombreSoporte NVARCHAR(250), tipoContenidoSoporte VARCHAR(50),
    tamanioSoporteBytes BIGINT, fechaRegistroSoporteUtc DATETIME2(7));

BEGIN TRANSACTION;
BEGIN TRY
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@session, N'QA HU035', @number, @sessionCode, 1, @group, @inicioSesion, DATEADD(HOUR, 1, @inicioSesion));
    INSERT dbo.Asistencia (id, estudianteGrupo, sesion) VALUES (@asisA, @egA, @session);
    INSERT dbo.Asistencia (id, estudianteGrupo, sesion) VALUES (@asisB, @egB, @session);
    -- Solo el estudiante A tiene DetalleAsistencia (causal SJC, no asistio); B no tiene detalle.
    INSERT dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin)
    VALUES (@detalleA, @detalleCode, @asisA, 0, @reasonSjc, @inicioSesion, DATEADD(HOUR, 1, @inicioSesion));
    INSERT dbo.SolicitudRevisionAsistencia (id, nombre, asistencia, fecha, estado, justificacionSolicitud, justificacionRespuesta)
    VALUES (@reqA, N'QA-HU035-A', @asisA, CAST(SYSUTCDATETIME() AS DATE), @estadoP, 'Cita medica QA', '');
    INSERT dbo.SolicitudRevisionAsistencia (id, nombre, asistencia, fecha, estado, justificacionSolicitud, justificacionRespuesta)
    VALUES (@reqB, N'QA-HU035-B', @asisB, CAST(SYSUTCDATETIME() AS DATE), @estadoP, 'Sin detalle QA', '');
    INSERT dbo.ArchivoSoporte (id, usuarioPropietario, solicitudRevisionAsistencia, nombreOriginal, tipoContenido, tamanioBytes,
        checksumSha256, estado, fechaRegistroUtc, fechaAdjuncionUtc, fechaCambioEstadoUtc, idCorrelacionRegistro, idCorrelacionAdjuncion)
    VALUES (@file, @userA, @reqA, N'incapacidad-hu035.pdf', 'application/pdf', 1234, @sha, 'ATTACHED',
        SYSUTCDATETIME(), SYSUTCDATETIME(), SYSUTCDATETIME(), @corr, @corrAdj);

    -- ---------------------------------------------------------------- DB-01 detalle del titular (forma y datos)
    INSERT INTO #r EXEC dbo.usp_consultar_detalle_solicitud_revision_docente
        @idSolicitud = @reqA, @idUsuarioEjecutor = @userT, @idCorrelacion = @corr;
    SELECT @rows = COUNT(*) FROM #r;
    SET @ok = IIF(@rows = 1, 1, 0);
    EXEC #hu35_expect 'DB01_ONE_ROW', @ok;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r WHERE idSolicitudRevisionAsistencia = @reqA AND nombreSolicitud = N'QA-HU035-A'
        AND codigoEstado = N'P' AND nombreEstado IS NOT NULL AND LEN(nombreEstado) > 0
        AND codigoRazonCausa = N'SJC' AND nombreRazonCausa IS NOT NULL AND asistio = 0
        AND idArchivoSoporte = @file AND nombreSoporte = N'incapacidad-hu035.pdf' AND tipoContenidoSoporte = 'application/pdf'
        AND tamanioSoporteBytes = 1234 AND fechaRegistroSoporteUtc IS NOT NULL
        AND idEstudiante = @studentA AND LEN(ISNULL(nombreEstudiante, N'')) > 0
        AND idSesion = @session AND numeroSesion = @number AND fechaHoraInicioSesion = @inicioSesion
        AND idGrupo = @group AND justificacionSolicitud = N'Cita medica QA' AND justificacionRespuesta = N''), 1, 0);
    EXEC #hu35_expect 'DB01_DATA_CAUSAL_AND_SUPPORT', @ok;
    SELECT @cols = STRING_AGG(CAST(name AS NVARCHAR(MAX)), N',') WITHIN GROUP (ORDER BY column_ordinal)
    FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID('dbo.usp_consultar_detalle_solicitud_revision_docente'), NULL);
    SET @ok = IIF(@cols = N'idSolicitudRevisionAsistencia,nombreSolicitud,fechaSolicitud,codigoEstado,nombreEstado,'
        + N'justificacionSolicitud,justificacionRespuesta,idEstudiante,nombreEstudiante,idSesion,numeroSesion,'
        + N'fechaHoraInicioSesion,procedenciaTemporalSesion,idGrupo,codigoGrupo,nombreGrupo,idAsignatura,codigoAsignatura,'
        + N'nombreAsignatura,asistio,codigoRazonCausa,nombreRazonCausa,idArchivoSoporte,nombreSoporte,tipoContenidoSoporte,'
        + N'tamanioSoporteBytes,fechaRegistroSoporteUtc', 1, 0);
    EXEC #hu35_expect 'DB01_COLUMN_NAMES_AND_ORDER', @ok;

    -- ---------------------------------------------------------------- DB-02 otro docente => 0 filas
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_consultar_detalle_solicitud_revision_docente
        @idSolicitud = @reqA, @idUsuarioEjecutor = @userT2, @idCorrelacion = @corr;
    SET @ok = IIF((SELECT COUNT(*) FROM #r) = 0, 1, 0);
    EXEC #hu35_expect 'DB02_OTHER_TEACHER_ZERO_ROWS', @ok;

    -- ---------------------------------------------------------------- DB-03 el estudiante y otros roles => 0 filas
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_consultar_detalle_solicitud_revision_docente
        @idSolicitud = @reqA, @idUsuarioEjecutor = @userA, @idCorrelacion = @corr;
    SET @ok = IIF((SELECT COUNT(*) FROM #r) = 0, 1, 0);
    EXEC #hu35_expect 'DB03_STUDENT_ZERO_ROWS', @ok;
    INSERT INTO #r EXEC dbo.usp_consultar_detalle_solicitud_revision_docente
        @idSolicitud = @reqA, @idUsuarioEjecutor = @userCoord, @idCorrelacion = @corr;
    SET @ok = IIF((SELECT COUNT(*) FROM #r) = 0, 1, 0);
    EXEC #hu35_expect 'DB03_COORDINATOR_ZERO_ROWS', @ok;

    -- ---------------------------------------------------------------- DB-04 id inexistente => 0 filas sin error
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_consultar_detalle_solicitud_revision_docente
        @idSolicitud = @corrAdj, @idUsuarioEjecutor = @userT, @idCorrelacion = @corr;
    SET @ok = IIF((SELECT COUNT(*) FROM #r) = 0, 1, 0);
    EXEC #hu35_expect 'DB04_UNKNOWN_ID_ZERO_ROWS', @ok;

    -- ---------------------------------------------------------------- DB-06 sin DetalleAsistencia ni soporte => 1 fila con NULL
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_consultar_detalle_solicitud_revision_docente
        @idSolicitud = @reqB, @idUsuarioEjecutor = @userT, @idCorrelacion = @corr;
    SET @ok = IIF((SELECT COUNT(*) FROM #r) = 1 AND EXISTS (SELECT 1 FROM #r WHERE idSolicitudRevisionAsistencia = @reqB
        AND codigoEstado = N'P' AND asistio IS NULL AND codigoRazonCausa IS NULL AND nombreRazonCausa IS NULL
        AND idArchivoSoporte IS NULL AND nombreSoporte IS NULL AND tipoContenidoSoporte IS NULL
        AND tamanioSoporteBytes IS NULL AND fechaRegistroSoporteUtc IS NULL), 1, 0);
    EXEC #hu35_expect 'DB06_WITHOUT_DETAIL_AND_SUPPORT', @ok;

    -- ---------------------------------------------------------------- DB-07 estado del soporte gobernado por el parametro
    UPDATE dbo.CatalogoParametro SET valor = 'ORPHAN' WHERE grupo = 'ARCHIVO' AND clave = 'ESTADO_ADJUNTO';
    SET @ok = IIF(@@ROWCOUNT = 1, 1, 0);
    EXEC #hu35_expect 'DB07_PARAMETER_EXISTS', @ok;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_consultar_detalle_solicitud_revision_docente
        @idSolicitud = @reqA, @idUsuarioEjecutor = @userT, @idCorrelacion = @corr;
    SET @ok = IIF((SELECT COUNT(*) FROM #r) = 1 AND EXISTS (SELECT 1 FROM #r WHERE idSolicitudRevisionAsistencia = @reqA
        AND codigoRazonCausa = N'SJC' AND idArchivoSoporte IS NULL AND nombreSoporte IS NULL), 1, 0);
    EXEC #hu35_expect 'DB07_NON_ATTACHED_STATE_NULL_SUPPORT', @ok;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;

IF EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE nombre IN (N'QA-HU035-A', N'QA-HU035-B'))
   OR EXISTS (SELECT 1 FROM dbo.ArchivoSoporte WHERE nombreOriginal = N'incapacidad-hu035.pdf')
   OR NOT EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = 'ARCHIVO' AND clave = 'ESTADO_ADJUNTO' AND valor = 'ATTACHED')
    THROW 52303, 'TEST FAILED: HU035_HU036 leaked fixture or parameter change.', 1;
-- DB-08 sin transacciones huerfanas
SET @ok = IIF(@@TRANCOUNT = 0, 1, 0);
EXEC #hu35_expect 'DB08_TRANCOUNT_ZERO', @ok;

-- ---------------------------------------------------------------- DB-05 parametros nulos => THROW 51000 (fuera de la transaccion)
DECLARE @errThrow INT, @okThrow BIT;
SET @errThrow = 0;
BEGIN TRY
    EXEC dbo.usp_consultar_detalle_solicitud_revision_docente @idSolicitud = NULL, @idUsuarioEjecutor = @userT, @idCorrelacion = @corr;
END TRY
BEGIN CATCH
    SET @errThrow = ERROR_NUMBER();
END CATCH
SET @okThrow = IIF(@errThrow = 51000, 1, 0);
EXEC #hu35_expect 'DB05_NULL_SOLICITUD_THROWS', @okThrow;
SET @errThrow = 0;
BEGIN TRY
    EXEC dbo.usp_consultar_detalle_solicitud_revision_docente @idSolicitud = @reqA, @idUsuarioEjecutor = NULL, @idCorrelacion = @corr;
END TRY
BEGIN CATCH
    SET @errThrow = ERROR_NUMBER();
END CATCH
SET @okThrow = IIF(@errThrow = 51000, 1, 0);
EXEC #hu35_expect 'DB05_NULL_EXECUTOR_THROWS', @okThrow;
SET @errThrow = 0;
BEGIN TRY
    EXEC dbo.usp_consultar_detalle_solicitud_revision_docente @idSolicitud = @reqA, @idUsuarioEjecutor = @userT, @idCorrelacion = NULL;
END TRY
BEGIN CATCH
    SET @errThrow = ERROR_NUMBER();
END CATCH
SET @okThrow = IIF(@errThrow = 51000, 1, 0);
EXEC #hu35_expect 'DB05_NULL_CORRELATION_THROWS', @okThrow;

SET @okThrow = IIF(@@TRANCOUNT = 0, 1, 0);
EXEC #hu35_expect 'DB08_TRANCOUNT_ZERO_FINAL', @okThrow;
DROP TABLE #r;
PRINT 'TEST_PASS:HU035_HU036_DB01_DETALLE_TITULAR';
PRINT 'TEST_PASS:HU035_HU036_DB02_DB03_DB04_AISLAMIENTO';
PRINT 'TEST_PASS:HU035_HU036_DB05_PARAMETROS_NULOS';
PRINT 'TEST_PASS:HU035_HU036_DB06_SIN_DETALLE_NI_SOPORTE';
PRINT 'TEST_PASS:HU035_HU036_DB07_ESTADO_ADJUNTO_PARAMETRIZADO';
PRINT 'TEST_PASS:HU035_HU036_DB08_TRANCOUNT_ZERO';
GO
