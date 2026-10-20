USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
-- El indice unico filtrado exige QUOTED_IDENTIFIER ON para todo DML directo (sqlcmd lo deja OFF).
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- LB-004D (ONE_TABLE): pruebas SQL del vinculo soporte <-> solicitud de revision.
-- Cada caso corre dentro de UNA transaccion con ROLLBACK final (sin datos persistentes) y usa
-- fixtures de la semilla local. Cubre: forma de la tabla, W1, W2, R1, R2, integridad, UTC,
-- permisos de minimo privilegio y que la v1 siga intacta.
-- La concurrencia (dos conexiones) vive en test/test_lb004d_concurrency.ps1.
-- ============================================================================
IF OBJECT_ID('tempdb..#lb4d_expect') IS NOT NULL DROP PROCEDURE #lb4d_expect;
GO
CREATE PROCEDURE #lb4d_expect @label VARCHAR(100), @ok BIT
AS
BEGIN
    IF @ok IS NULL OR @ok <> 1
    BEGIN
        DECLARE @mensaje NVARCHAR(400) = CONCAT('TEST FAILED: LB004D_', @label);
        THROW 52200, @mensaje, 1;
    END
END;
GO

DECLARE @group UNIQUEIDENTIFIER, @group2 UNIQUEIDENTIFIER, @teacher UNIQUEIDENTIFIER, @teacher2 UNIQUEIDENTIFIER;
DECLARE @studentA UNIQUEIDENTIFIER, @studentB UNIQUEIDENTIFIER, @studentC UNIQUEIDENTIFIER;
DECLARE @userA UNIQUEIDENTIFIER, @userB UNIQUEIDENTIFIER, @userC UNIQUEIDENTIFIER;
DECLARE @userT UNIQUEIDENTIFIER, @userT2 UNIQUEIDENTIFIER;
DECLARE @userAdmin UNIQUEIDENTIFIER, @userCoord UNIQUEIDENTIFIER, @userDean UNIQUEIDENTIFIER;

SELECT TOP 1 @group = g.id, @teacher = g.docente
FROM dbo.Grupo g
WHERE (SELECT COUNT(*) FROM dbo.uv_estudiante_grupo x WHERE x.idGrupo = g.id AND x.codigoEstadoEstudiante = 'A') >= 2
ORDER BY (SELECT COUNT(*) FROM dbo.uv_estudiante_grupo x WHERE x.idGrupo = g.id) ASC, g.id;

SELECT @studentA = z.idEstudiante FROM (
    SELECT idEstudiante, ROW_NUMBER() OVER (ORDER BY idEstudiante) rn
    FROM dbo.uv_estudiante_grupo WHERE idGrupo = @group AND codigoEstadoEstudiante = 'A') z WHERE z.rn = 1;
SELECT @studentB = z.idEstudiante FROM (
    SELECT idEstudiante, ROW_NUMBER() OVER (ORDER BY idEstudiante) rn
    FROM dbo.uv_estudiante_grupo WHERE idGrupo = @group AND codigoEstadoEstudiante = 'A') z WHERE z.rn = 2;

SELECT TOP 1 @group2 = eg.idGrupo, @studentC = eg.idEstudiante
FROM dbo.uv_estudiante_grupo eg
WHERE eg.idGrupo <> @group AND eg.codigoEstadoEstudiante = 'A'
  AND NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo y WHERE y.idGrupo = @group AND y.idEstudiante = eg.idEstudiante)
ORDER BY eg.idGrupo, eg.idEstudiante;

SELECT TOP 1 @teacher2 = d.id FROM dbo.Docente d WHERE d.id <> @teacher ORDER BY d.id;
SELECT @userA = usuario FROM dbo.Estudiante WHERE id = @studentA;
SELECT @userB = usuario FROM dbo.Estudiante WHERE id = @studentB;
SELECT @userC = usuario FROM dbo.Estudiante WHERE id = @studentC;
SELECT @userT = usuario FROM dbo.Docente WHERE id = @teacher;
SELECT @userT2 = usuario FROM dbo.Docente WHERE id = @teacher2;
SELECT TOP 1 @userAdmin = usuario FROM dbo.Administrador ORDER BY id;
SELECT TOP 1 @userCoord = usuario FROM dbo.Coordinador ORDER BY id;
SELECT TOP 1 @userDean = usuario FROM dbo.Decano ORDER BY id;

IF @group IS NULL OR @group2 IS NULL OR @teacher IS NULL OR @teacher2 IS NULL OR @studentA IS NULL OR @studentB IS NULL
   OR @studentC IS NULL OR @userA IS NULL OR @userB IS NULL OR @userC IS NULL OR @userT IS NULL OR @userT2 IS NULL
   OR @userAdmin IS NULL OR @userCoord IS NULL OR @userDean IS NULL
    THROW 52201, 'TEST FAILED: LB004D fixture missing (seed data).', 1;

DECLARE @session UNIQUEIDENTIFIER = NEWID(), @session2 UNIQUEIDENTIFIER = NEWID();
DECLARE @number INT = 1 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @group);
DECLARE @number2 INT = 1 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @group2);
DECLARE @sessionCode NVARCHAR(50) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8);
DECLARE @sessionCode2 NVARCHAR(50) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8);
DECLARE @inicioSesion DATETIME2(7) = '2026-10-19T15:30:45.1234567';

DECLARE @corr UNIQUEIDENTIFIER, @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000);
DECLARE @file1 UNIQUEIDENTIFIER = NEWID(), @file2 UNIQUEIDENTIFIER = NEWID(), @fileB UNIQUEIDENTIFIER = NEWID();
DECLARE @sha1 CHAR(64) = LOWER(CONVERT(CHAR(64), HASHBYTES('SHA2_256', 'lb004d-1'), 2));
DECLARE @sha2 CHAR(64) = LOWER(CONVERT(CHAR(64), HASHBYTES('SHA2_256', 'lb004d-2'), 2));
DECLARE @t0 DATETIME2(7), @t1 DATETIME2(7), @n INT, @ok BIT, @err INT, @req UNIQUEIDENTIFIER, @req2 UNIQUEIDENTIFIER;

CREATE TABLE #w (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(MAX),
    mensajeTecnicoResultado NVARCHAR(MAX), estadoResultado INT NOT NULL);
CREATE TABLE #r1 (idArchivoSoporte UNIQUEIDENTIFIER, estado VARCHAR(10), nombreOriginal NVARCHAR(250), tipoContenido VARCHAR(50),
    tamanioBytes BIGINT, checksumSha256 CHAR(64), fechaRegistroUtc DATETIME2(7), fechaAdjuncionUtc DATETIME2(7),
    idSolicitudRevisionAsistencia UNIQUEIDENTIFIER, relacionAcceso VARCHAR(20));
CREATE TABLE #r2 (idSolicitudRevisionAsistencia UNIQUEIDENTIFIER, nombreSolicitud NVARCHAR(50), fechaSolicitud DATE,
    codigoEstado CHAR(1), nombreEstado NVARCHAR(100), justificacionSolicitud NVARCHAR(MAX), justificacionRespuesta NVARCHAR(MAX),
    idEstudiante UNIQUEIDENTIFIER, nombreEstudiante NVARCHAR(400), idSesion UNIQUEIDENTIFIER, numeroSesion INT,
    fechaHoraInicioSesion DATETIME2(7), procedenciaTemporalSesion NVARCHAR(24), idGrupo UNIQUEIDENTIFIER, codigoGrupo INT,
    nombreGrupo NVARCHAR(100), idAsignatura UNIQUEIDENTIFIER, codigoAsignatura NVARCHAR(100), nombreAsignatura NVARCHAR(100),
    idArchivoSoporte UNIQUEIDENTIFIER, nombreSoporte NVARCHAR(250), tipoContenidoSoporte VARCHAR(50),
    tamanioSoporteBytes BIGINT, fechaRegistroSoporteUtc DATETIME2(7), totalRegistros INT);

BEGIN TRANSACTION;
BEGIN TRY
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@session, N'QA Soporte', @number, @sessionCode, 1, @group, @inicioSesion, DATEADD(HOUR, 1, @inicioSesion));
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@session2, N'QA Soporte 2', @number2, @sessionCode2, 1, @group2, @inicioSesion, DATEADD(HOUR, 1, @inicioSesion));

    -- ---------------------------------------------------------------- forma de la tabla (ONE_TABLE)
    SET @ok = IIF(
        (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.ArchivoSoporte')) = 13
        AND (SELECT COUNT(*) FROM sys.columns c JOIN sys.types t ON t.user_type_id = c.user_type_id
             WHERE c.object_id = OBJECT_ID('dbo.ArchivoSoporte') AND c.name IN ('fechaRegistroUtc', 'fechaAdjuncionUtc', 'fechaCambioEstadoUtc')
               AND t.name = 'datetime2' AND c.scale = 7) = 3
        AND EXISTS (SELECT 1 FROM sys.key_constraints WHERE parent_object_id = OBJECT_ID('dbo.ArchivoSoporte') AND type = 'PK')
        AND (SELECT COUNT(*) FROM sys.foreign_keys WHERE parent_object_id = OBJECT_ID('dbo.ArchivoSoporte')
             AND name IN ('FK_ArchivoSoporte_Usuario', 'FK_ArchivoSoporte_SolicitudRevisionAsistencia')
             AND delete_referential_action = 0) = 2
        AND EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.ArchivoSoporte') AND name = 'UX_ArchivoSoporte_Solicitud'
                    AND is_unique = 1 AND has_filter = 1)
        AND NOT EXISTS (SELECT 1 FROM sys.tables WHERE name LIKE 'ArchivoSoporte%' AND name <> 'ArchivoSoporte'), 1, 0);
    EXEC #lb4d_expect 'SCHEMA_SHAPE', @ok;

    -- ---------------------------------------------------------------- W1 registrar (valido, UTC)
    SET @corr = NEWID();
    SET @t0 = SYSUTCDATETIME();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'ArchivoSoporte',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #w EXEC dbo.usp_registrar_archivo_soporte @idArchivoSoporte = @file1, @nombreOriginal = N'evidencia.pdf',
        @tipoContenido = 'application/pdf', @tamanioBytes = 1234, @checksumSha256 = @sha1, @idCorrelacion = @corr,
        @idUsuarioEjecutor = @userA;
    SET @t1 = SYSUTCDATETIME();
    SET @ok = IIF((SELECT COUNT(*) FROM #w WHERE idCorrelacion = @corr AND estadoResultado = 1 AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) = 1, 1, 0);
    EXEC #lb4d_expect 'W1_VALID_RESULT', @ok;
    SET @ok = IIF(EXISTS (SELECT 1 FROM dbo.ArchivoSoporte WHERE id = @file1 AND usuarioPropietario = @userA AND estado = 'DRAFT'
        AND solicitudRevisionAsistencia IS NULL AND fechaAdjuncionUtc IS NULL AND idCorrelacionAdjuncion IS NULL
        AND idCorrelacionRegistro = @corr AND tipoContenido = 'application/pdf' AND tamanioBytes = 1234 AND checksumSha256 = @sha1
        AND fechaRegistroUtc BETWEEN @t0 AND @t1 AND fechaCambioEstadoUtc BETWEEN @t0 AND @t1), 1, 0);
    EXEC #lb4d_expect 'W1_VALID_ROW_UTC', @ok;

    -- ---------------------------------------------------------------- W1 idempotencia y conflictos (ARC_002)
    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_registrar_archivo_soporte @idArchivoSoporte = @file1, @nombreOriginal = N'evidencia.pdf',
        @tipoContenido = 'application/pdf', @tamanioBytes = 1234, @checksumSha256 = @sha1, @idCorrelacion = @corr,
        @idUsuarioEjecutor = @userA;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w WHERE estadoResultado = 1) AND (SELECT COUNT(*) FROM dbo.ArchivoSoporte WHERE id = @file1) = 1
        AND EXISTS (SELECT 1 FROM dbo.ArchivoSoporte WHERE id = @file1 AND idCorrelacionRegistro <> @corr), 1, 0);
    EXEC #lb4d_expect 'W1_IDEMPOTENT_RETRY', @ok;

    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ARC_002',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_registrar_archivo_soporte @idArchivoSoporte = @file1, @nombreOriginal = N'evidencia.pdf',
        @tipoContenido = 'application/pdf', @tamanioBytes = 1234, @checksumSha256 = @sha2, @idCorrelacion = @corr,
        @idUsuarioEjecutor = @userA;
    SET @ok = IIF((SELECT COUNT(*) FROM #w WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) = 1
        AND EXISTS (SELECT 1 FROM dbo.ArchivoSoporte WHERE id = @file1 AND checksumSha256 = @sha1), 1, 0);
    EXEC #lb4d_expect 'W1_CONFLICT_OTHER_METADATA', @ok;

    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_registrar_archivo_soporte @idArchivoSoporte = @file1, @nombreOriginal = N'evidencia.pdf',
        @tipoContenido = 'application/pdf', @tamanioBytes = 1234, @checksumSha256 = @sha1, @idCorrelacion = @corr,
        @idUsuarioEjecutor = @userB;
    SET @ok = IIF((SELECT COUNT(*) FROM #w WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg) = 1
        AND EXISTS (SELECT 1 FROM dbo.ArchivoSoporte WHERE id = @file1 AND usuarioPropietario = @userA), 1, 0);
    EXEC #lb4d_expect 'W1_CONFLICT_OTHER_OWNER', @ok;

    -- ---------------------------------------------------------------- W1 metadata invalida y perfil (ARC_003 / GEN_002 / SEC_001)
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ARC_003',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    DECLARE @bad TABLE (id INT IDENTITY, nombre NVARCHAR(250), tipo VARCHAR(50), tamano BIGINT, sha CHAR(64));
    INSERT @bad (nombre, tipo, tamano, sha) VALUES
        (N'a.exe', 'application/x-msdownload', 10, @sha1),
        (N'a.pdf', 'application/pdf', 0, @sha1),
        (N'a.pdf', 'application/pdf', 5242881, @sha1),
        (N'a.pdf', 'application/pdf', 10, UPPER(@sha1)),
        (N'a.pdf', 'application/pdf', 10, LEFT(@sha1, 63)),
        (N'   ', 'application/pdf', 10, @sha1),
        (N'a.svg', 'image/svg+xml', 10, @sha1);
    DECLARE @i INT = 1, @maxBad INT = (SELECT COUNT(*) FROM @bad);
    DECLARE @bn NVARCHAR(250), @bt VARCHAR(50), @bz BIGINT, @bs CHAR(64), @da UNIQUEIDENTIFIER, @du UNIQUEIDENTIFIER;
    WHILE @i <= @maxBad
    BEGIN
        TRUNCATE TABLE #w;
        SET @corr = NEWID();
        DECLARE @nid UNIQUEIDENTIFIER = NEWID();
        SELECT @bn = nombre, @bt = tipo, @bz = tamano, @bs = sha FROM @bad WHERE id = @i;
        INSERT INTO #w EXEC dbo.usp_registrar_archivo_soporte @idArchivoSoporte = @nid,
            @nombreOriginal = @bn, @tipoContenido = @bt, @tamanioBytes = @bz, @checksumSha256 = @bs,
            @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
        SET @ok = IIF((SELECT COUNT(*) FROM #w WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg) = 1
            AND NOT EXISTS (SELECT 1 FROM dbo.ArchivoSoporte WHERE id = @nid), 1, 0);
        EXEC #lb4d_expect 'W1_INVALID_METADATA', @ok;
        SET @i += 1;
    END

    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    SET @nid = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #w EXEC dbo.usp_registrar_archivo_soporte @idArchivoSoporte = @nid, @nombreOriginal = N'a.pdf',
        @tipoContenido = 'application/pdf', @tamanioBytes = 10, @checksumSha256 = @sha1, @idCorrelacion = @corr,
        @idUsuarioEjecutor = NULL;
    SET @ok = IIF((SELECT COUNT(*) FROM #w WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg) = 1
        AND NOT EXISTS (SELECT 1 FROM dbo.ArchivoSoporte WHERE id = @nid), 1, 0);
    EXEC #lb4d_expect 'W1_NULL_EXECUTOR', @ok;

    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_registrar_archivo_soporte @idArchivoSoporte = @nid, @nombreOriginal = N'a.pdf',
        @tipoContenido = 'application/pdf', @tamanioBytes = 10, @checksumSha256 = @sha1, @idCorrelacion = @corr,
        @idUsuarioEjecutor = @userT;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w WHERE estadoResultado = 0) AND NOT EXISTS (SELECT 1 FROM dbo.ArchivoSoporte WHERE id = @nid), 1, 0);
    EXEC #lb4d_expect 'W1_NON_STUDENT_PROFILE', @ok;

    TRUNCATE TABLE #w;
    SET @corr = '00000000-0000-0000-0000-000000000000';
    INSERT INTO #w EXEC dbo.usp_registrar_archivo_soporte @idArchivoSoporte = @nid, @nombreOriginal = N'a.pdf',
        @tipoContenido = 'application/pdf', @tamanioBytes = 10, @checksumSha256 = @sha1, @idCorrelacion = @corr,
        @idUsuarioEjecutor = @userA;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w WHERE estadoResultado = 0) AND NOT EXISTS (SELECT 1 FROM dbo.ArchivoSoporte WHERE id = @nid), 1, 0);
    EXEC #lb4d_expect 'W1_EMPTY_CORRELATION', @ok;

    -- fileB: DRAFT de B (ajeno para A); file2: DRAFT de A
    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_registrar_archivo_soporte @idArchivoSoporte = @fileB, @nombreOriginal = N'de-b.png',
        @tipoContenido = 'image/png', @tamanioBytes = 99, @checksumSha256 = @sha2, @idCorrelacion = @corr, @idUsuarioEjecutor = @userB;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w WHERE estadoResultado = 1), 1, 0);
    EXEC #lb4d_expect 'W1_FIXTURE_B', @ok;
    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_registrar_archivo_soporte @idArchivoSoporte = @file2, @nombreOriginal = N'segundo.jpg',
        @tipoContenido = 'image/jpeg', @tamanioBytes = 77, @checksumSha256 = @sha2, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w WHERE estadoResultado = 1), 1, 0);
    EXEC #lb4d_expect 'W1_FIXTURE_A2', @ok;

    -- ---------------------------------------------------------------- W2 sin soporte (opcional)
    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'SolicitudRevisionAsistencia',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #w EXEC dbo.usp_radicar_solicitud_revision_asistencia_v2 @idEstudiante = @studentA, @idSesion = @session,
        @categoria = N'ASISTENCIA', @justificacion = N'Sin soporte QA', @idArchivoSoporte = NULL, @idCorrelacion = @corr,
        @idUsuarioEjecutor = @userA;
    SET @ok = IIF((SELECT COUNT(*) FROM #w WHERE idCorrelacion = @corr AND estadoResultado = 1 AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) = 1, 1, 0);
    EXEC #lb4d_expect 'W2_NO_SUPPORT_RESULT', @ok;
    SELECT @req = sra.id FROM dbo.SolicitudRevisionAsistencia sra
    WHERE sra.justificacionSolicitud = N'Sin soporte QA';
    SET @ok = IIF(@req IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia r JOIN dbo.Estado e ON e.id = r.estado
        WHERE r.id = @req AND e.codigo = 'P')
        AND NOT EXISTS (SELECT 1 FROM dbo.ArchivoSoporte WHERE solicitudRevisionAsistencia = @req), 1, 0);
    EXEC #lb4d_expect 'W2_NO_SUPPORT_PENDING', @ok;

    -- R2 del docente titular: reclamo sin soporte => columnas de soporte NULL
    TRUNCATE TABLE #r2;
    SET @corr = NEWID();
    INSERT INTO #r2 EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @codigoEstado = NULL, @numeroPagina = 1, @tamanoPagina = 100;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r2 WHERE idSolicitudRevisionAsistencia = @req AND idArchivoSoporte IS NULL
        AND nombreSoporte IS NULL AND tipoContenidoSoporte IS NULL AND tamanioSoporteBytes IS NULL
        AND idEstudiante = @studentA AND idSesion = @session AND idGrupo = @group AND codigoEstado = 'P'
        AND fechaHoraInicioSesion = @inicioSesion AND procedenciaTemporalSesion IS NULL), 1, 0);
    EXEC #lb4d_expect 'R2_WITHOUT_SUPPORT_AND_UTC_PRECISION', @ok;

    -- ---------------------------------------------------------------- W2 con soporte propio => ATTACHED
    TRUNCATE TABLE #w;
    DECLARE @corrAttach UNIQUEIDENTIFIER = NEWID();
    SET @t0 = SYSUTCDATETIME();
    INSERT INTO #w EXEC dbo.usp_radicar_solicitud_revision_asistencia_v2 @idEstudiante = @studentA, @idSesion = @session,
        @categoria = N'ASISTENCIA', @justificacion = N'Con soporte QA', @idArchivoSoporte = @file1, @idCorrelacion = @corrAttach,
        @idUsuarioEjecutor = @userA;
    SET @t1 = SYSUTCDATETIME();
    SET @ok = IIF((SELECT COUNT(*) FROM #w WHERE idCorrelacion = @corrAttach AND estadoResultado = 1 AND mensajeUsuarioResultado = @userMsg) = 1, 1, 0);
    EXEC #lb4d_expect 'W2_ATTACH_RESULT', @ok;
    SELECT @req2 = id FROM dbo.SolicitudRevisionAsistencia WHERE justificacionSolicitud = N'Con soporte QA';
    SET @ok = IIF(@req2 IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.ArchivoSoporte WHERE id = @file1 AND estado = 'ATTACHED'
        AND solicitudRevisionAsistencia = @req2 AND idCorrelacionAdjuncion = @corrAttach
        AND fechaAdjuncionUtc BETWEEN @t0 AND @t1 AND fechaCambioEstadoUtc BETWEEN @t0 AND @t1
        AND fechaAdjuncionUtc >= fechaRegistroUtc), 1, 0);
    EXEC #lb4d_expect 'W2_ATTACH_STATE_UTC', @ok;

    -- reintento con la MISMA correlacion => idempotente, sin segunda solicitud
    TRUNCATE TABLE #w;
    INSERT INTO #w EXEC dbo.usp_radicar_solicitud_revision_asistencia_v2 @idEstudiante = @studentA, @idSesion = @session,
        @categoria = N'ASISTENCIA', @justificacion = N'Con soporte QA', @idArchivoSoporte = @file1, @idCorrelacion = @corrAttach,
        @idUsuarioEjecutor = @userA;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w WHERE estadoResultado = 1)
        AND (SELECT COUNT(*) FROM dbo.SolicitudRevisionAsistencia WHERE justificacionSolicitud = N'Con soporte QA') = 1, 1, 0);
    EXEC #lb4d_expect 'W2_RETRY_SAME_CORRELATION_IDEMPOTENT', @ok;

    -- doble asociacion con OTRA correlacion => ARC_001 y sin segunda solicitud
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ARC_001',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_radicar_solicitud_revision_asistencia_v2 @idEstudiante = @studentA, @idSesion = @session,
        @categoria = N'ASISTENCIA', @justificacion = N'Doble QA', @idArchivoSoporte = @file1, @idCorrelacion = @corr,
        @idUsuarioEjecutor = @userA;
    SET @ok = IIF((SELECT COUNT(*) FROM #w WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) = 1
        AND NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE justificacionSolicitud = N'Doble QA')
        AND EXISTS (SELECT 1 FROM dbo.ArchivoSoporte WHERE id = @file1 AND solicitudRevisionAsistencia = @req2), 1, 0);
    EXEC #lb4d_expect 'W2_DOUBLE_ATTACH_REJECTED', @ok;

    -- archivo ajeno (DRAFT de B) e inexistente: mismo mensaje ARC_001, sin solicitud y B sigue DRAFT
    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_radicar_solicitud_revision_asistencia_v2 @idEstudiante = @studentA, @idSesion = @session,
        @categoria = N'ASISTENCIA', @justificacion = N'Ajeno QA', @idArchivoSoporte = @fileB, @idCorrelacion = @corr,
        @idUsuarioEjecutor = @userA;
    SET @ok = IIF((SELECT COUNT(*) FROM #w WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg) = 1
        AND NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE justificacionSolicitud = N'Ajeno QA')
        AND EXISTS (SELECT 1 FROM dbo.ArchivoSoporte WHERE id = @fileB AND estado = 'DRAFT' AND solicitudRevisionAsistencia IS NULL), 1, 0);
    EXEC #lb4d_expect 'W2_FOREIGN_FILE_REJECTED', @ok;
    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_radicar_solicitud_revision_asistencia_v2 @idEstudiante = @studentA, @idSesion = @session,
        @categoria = N'ASISTENCIA', @justificacion = N'Inexistente QA', @idArchivoSoporte = @nid, @idCorrelacion = @corr,
        @idUsuarioEjecutor = @userA;
    SET @ok = IIF((SELECT COUNT(*) FROM #w WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg) = 1
        AND NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE justificacionSolicitud = N'Inexistente QA'), 1, 0);
    EXEC #lb4d_expect 'W2_MISSING_FILE_SAME_MESSAGE', @ok;

    -- estudiante != ejecutor (ARC_005) y matricula/sesion invalidas: sin solicitud y file2 sigue DRAFT
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ARC_005',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_radicar_solicitud_revision_asistencia_v2 @idEstudiante = @studentB, @idSesion = @session,
        @categoria = N'ASISTENCIA', @justificacion = N'Suplantacion QA', @idArchivoSoporte = @file2, @idCorrelacion = @corr,
        @idUsuarioEjecutor = @userA;
    SET @ok = IIF((SELECT COUNT(*) FROM #w WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @userMsg) = 1
        AND NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE justificacionSolicitud = N'Suplantacion QA')
        AND EXISTS (SELECT 1 FROM dbo.ArchivoSoporte WHERE id = @file2 AND estado = 'DRAFT'), 1, 0);
    EXEC #lb4d_expect 'W2_STUDENT_NOT_EXECUTOR', @ok;

    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_radicar_solicitud_revision_asistencia_v2 @idEstudiante = @studentA, @idSesion = @nid,
        @categoria = N'ASISTENCIA', @justificacion = N'Sesion inexistente QA', @idArchivoSoporte = @file2, @idCorrelacion = @corr,
        @idUsuarioEjecutor = @userA;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w WHERE estadoResultado = 0)
        AND NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE justificacionSolicitud = N'Sesion inexistente QA')
        AND EXISTS (SELECT 1 FROM dbo.ArchivoSoporte WHERE id = @file2 AND estado = 'DRAFT'), 1, 0);
    EXEC #lb4d_expect 'W2_MISSING_SESSION', @ok;
    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_radicar_solicitud_revision_asistencia_v2 @idEstudiante = @studentA, @idSesion = @session2,
        @categoria = N'ASISTENCIA', @justificacion = N'Sin matricula QA', @idArchivoSoporte = @file2, @idCorrelacion = @corr,
        @idUsuarioEjecutor = @userA;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w WHERE estadoResultado = 0)
        AND NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE justificacionSolicitud = N'Sin matricula QA')
        AND EXISTS (SELECT 1 FROM dbo.ArchivoSoporte WHERE id = @file2 AND estado = 'DRAFT'), 1, 0);
    EXEC #lb4d_expect 'W2_NOT_ENROLLED', @ok;
    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_radicar_solicitud_revision_asistencia_v2 @idEstudiante = @studentA, @idSesion = @session,
        @categoria = N'ASISTENCIA', @justificacion = N'Docente QA', @idArchivoSoporte = @file2, @idCorrelacion = @corr,
        @idUsuarioEjecutor = @userT;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w WHERE estadoResultado = 0)
        AND NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE justificacionSolicitud = N'Docente QA'), 1, 0);
    EXEC #lb4d_expect 'W2_NON_STUDENT_PROFILE', @ok;

    -- ---------------------------------------------------------------- R1 matriz de autorizacion
    -- file1 = ATTACHED (A, solicitud de la sesion en el grupo de @teacher); fileB = DRAFT de B
    TRUNCATE TABLE #r1;
    SET @corr = NEWID();
    INSERT INTO #r1 EXEC dbo.usp_consultar_archivo_soporte_autorizado @idArchivoSoporte = @file1, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SET @ok = IIF((SELECT COUNT(*) FROM #r1 WHERE idArchivoSoporte = @file1 AND estado = 'ATTACHED' AND relacionAcceso = 'PROPIETARIO'
        AND nombreOriginal = N'evidencia.pdf' AND tipoContenido = 'application/pdf' AND tamanioBytes = 1234
        AND checksumSha256 = @sha1 AND idSolicitudRevisionAsistencia = @req2 AND fechaAdjuncionUtc IS NOT NULL) = 1, 1, 0);
    EXEC #lb4d_expect 'R1_OWNER_ATTACHED', @ok;

    TRUNCATE TABLE #r1;
    INSERT INTO #r1 EXEC dbo.usp_consultar_archivo_soporte_autorizado @idArchivoSoporte = @fileB, @idCorrelacion = @corr, @idUsuarioEjecutor = @userB;
    SET @ok = IIF((SELECT COUNT(*) FROM #r1 WHERE estado = 'DRAFT' AND relacionAcceso = 'PROPIETARIO') = 1, 1, 0);
    EXEC #lb4d_expect 'R1_OWNER_DRAFT', @ok;

    TRUNCATE TABLE #r1;
    INSERT INTO #r1 EXEC dbo.usp_consultar_archivo_soporte_autorizado @idArchivoSoporte = @file1, @idCorrelacion = @corr, @idUsuarioEjecutor = @userT;
    SET @ok = IIF((SELECT COUNT(*) FROM #r1 WHERE idArchivoSoporte = @file1 AND relacionAcceso = 'DOCENTE_TITULAR') = 1, 1, 0);
    EXEC #lb4d_expect 'R1_TEACHER_TITULAR', @ok;

    -- cero filas: docente titular sobre DRAFT, docente ajeno, otro estudiante del MISMO grupo, estudiante de otro grupo,
    -- administrador, coordinador, decano, inexistente
    DECLARE @denied TABLE (id INT IDENTITY, archivo UNIQUEIDENTIFIER, usuario UNIQUEIDENTIFIER, caso VARCHAR(40));
    INSERT @denied (archivo, usuario, caso) VALUES
        (@fileB, @userT, 'TEACHER_ON_DRAFT'), (@file1, @userT2, 'TEACHER_NOT_TITULAR'), (@file1, @userB, 'STUDENT_SAME_GROUP'),
        (@file1, @userC, 'STUDENT_OTHER_GROUP'), (@file1, @userAdmin, 'ADMIN'), (@file1, @userCoord, 'COORDINATOR'),
        (@file1, @userDean, 'DEAN'), (@nid, @userA, 'NONEXISTENT'), (@fileB, @userA, 'OTHER_STUDENT_DRAFT');
    SET @i = 1; SET @maxBad = (SELECT COUNT(*) FROM @denied);
    WHILE @i <= @maxBad
    BEGIN
        TRUNCATE TABLE #r1;
        SELECT @da = archivo, @du = usuario FROM @denied WHERE id = @i;
        INSERT INTO #r1 EXEC dbo.usp_consultar_archivo_soporte_autorizado @idArchivoSoporte = @da,
            @idCorrelacion = @corr, @idUsuarioEjecutor = @du;
        SET @ok = IIF(NOT EXISTS (SELECT 1 FROM #r1), 1, 0);
        DECLARE @etiqueta VARCHAR(100) = CONCAT('R1_DENIED_', (SELECT caso FROM @denied WHERE id = @i));
        EXEC #lb4d_expect @etiqueta, @ok;
        SET @i += 1;
    END

    -- ORPHAN: inaccesible incluso para el propietario
    UPDATE dbo.ArchivoSoporte SET estado = 'ORPHAN' WHERE id = @file2;
    TRUNCATE TABLE #r1;
    INSERT INTO #r1 EXEC dbo.usp_consultar_archivo_soporte_autorizado @idArchivoSoporte = @file2, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SET @ok = IIF(NOT EXISTS (SELECT 1 FROM #r1), 1, 0);
    EXEC #lb4d_expect 'R1_ORPHAN_NOT_ACCESSIBLE', @ok;
    UPDATE dbo.ArchivoSoporte SET estado = 'DRAFT' WHERE id = @file2;


    -- ---------------------------------------------------------------- R2: titularidad, soporte, paginacion y filtros
    TRUNCATE TABLE #r2;
    INSERT INTO #r2 EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @codigoEstado = NULL, @numeroPagina = 1, @tamanoPagina = 100;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #r2 WHERE idSolicitudRevisionAsistencia = @req2 AND idArchivoSoporte = @file1
        AND nombreSoporte = N'evidencia.pdf' AND tipoContenidoSoporte = 'application/pdf' AND tamanioSoporteBytes = 1234
        AND fechaRegistroSoporteUtc IS NOT NULL
        AND nombreEstudiante IS NOT NULL AND nombreEstudiante <> N'')
        AND EXISTS (SELECT 1 FROM #r2 WHERE idSolicitudRevisionAsistencia = @req AND idArchivoSoporte IS NULL)
        AND NOT EXISTS (SELECT 1 FROM #r2 WHERE idGrupo <> @group)
        AND (SELECT MAX(totalRegistros) FROM #r2) >= 2, 1, 0);
    EXEC #lb4d_expect 'R2_TEACHER_SCOPE_AND_SUPPORT', @ok;

    -- R2 de otro docente: ninguna solicitud de este grupo; de un estudiante: nada; filtro de estado; paginacion
    TRUNCATE TABLE #r2;
    INSERT INTO #r2 EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userT2, @idCorrelacion = @corr,
        @codigoEstado = NULL, @numeroPagina = 1, @tamanoPagina = 100;
    SET @ok = IIF(NOT EXISTS (SELECT 1 FROM #r2 WHERE idSolicitudRevisionAsistencia IN (@req, @req2)), 1, 0);
    EXEC #lb4d_expect 'R2_OTHER_TEACHER_ZERO_ROWS', @ok;
    TRUNCATE TABLE #r2;
    INSERT INTO #r2 EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userA, @idCorrelacion = @corr,
        @codigoEstado = NULL, @numeroPagina = 1, @tamanoPagina = 100;
    SET @ok = IIF(NOT EXISTS (SELECT 1 FROM #r2), 1, 0);
    EXEC #lb4d_expect 'R2_STUDENT_ZERO_ROWS', @ok;
    TRUNCATE TABLE #r2;
    INSERT INTO #r2 EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userAdmin, @idCorrelacion = @corr,
        @codigoEstado = NULL, @numeroPagina = 1, @tamanoPagina = 100;
    SET @ok = IIF(NOT EXISTS (SELECT 1 FROM #r2), 1, 0);
    EXEC #lb4d_expect 'R2_ADMIN_ZERO_ROWS', @ok;

    TRUNCATE TABLE #r2;
    INSERT INTO #r2 EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @codigoEstado = N'A', @numeroPagina = 1, @tamanoPagina = 100;
    SET @ok = IIF(NOT EXISTS (SELECT 1 FROM #r2 WHERE idSolicitudRevisionAsistencia IN (@req, @req2)), 1, 0);
    EXEC #lb4d_expect 'R2_STATE_FILTER_EXCLUDES', @ok;
    TRUNCATE TABLE #r2;
    INSERT INTO #r2 EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @codigoEstado = N'P', @numeroPagina = 1, @tamanoPagina = 1;
    SET @n = (SELECT COUNT(*) FROM #r2);
    DECLARE @firstPage UNIQUEIDENTIFIER = (SELECT TOP 1 idSolicitudRevisionAsistencia FROM #r2);
    TRUNCATE TABLE #r2;
    INSERT INTO #r2 EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @userT, @idCorrelacion = @corr,
        @codigoEstado = N'P', @numeroPagina = 2, @tamanoPagina = 1;
    SET @ok = IIF(@n = 1 AND (SELECT COUNT(*) FROM #r2) = 1 AND (SELECT TOP 1 totalRegistros FROM #r2) >= 2
        AND (SELECT TOP 1 idSolicitudRevisionAsistencia FROM #r2) <> @firstPage, 1, 0);
    EXEC #lb4d_expect 'R2_REAL_PAGINATION', @ok;
    SET @ok = IIF(NOT EXISTS (SELECT 1 FROM tempdb.sys.columns WHERE object_id = OBJECT_ID('tempdb..#r2') AND name LIKE '%orreo%'), 1, 0);
    EXEC #lb4d_expect 'R2_NO_EMAIL_COLUMN', @ok;

    -- ---------------------------------------------------------------- integridad referencial (INSERT directo)
    DECLARE @fk UNIQUEIDENTIFIER = NEWID();
    SET @err = 0;
    BEGIN TRY
        INSERT dbo.ArchivoSoporte (id, usuarioPropietario, solicitudRevisionAsistencia, nombreOriginal, tipoContenido, tamanioBytes,
            checksumSha256, estado, fechaRegistroUtc, fechaAdjuncionUtc, fechaCambioEstadoUtc, idCorrelacionRegistro, idCorrelacionAdjuncion)
        VALUES (@fk, NEWID(), NULL, N'x.pdf', 'application/pdf', 1, @sha1, 'DRAFT', SYSUTCDATETIME(), NULL, SYSUTCDATETIME(), NEWID(), NULL);
    END TRY
    BEGIN CATCH
        SET @err = ERROR_NUMBER();
    END CATCH
    SET @ok = IIF(@err = 547, 1, 0);
    EXEC #lb4d_expect 'INTEGRITY_FK_USUARIO', @ok;

    SET @err = 0;
    BEGIN TRY
        INSERT dbo.ArchivoSoporte (id, usuarioPropietario, solicitudRevisionAsistencia, nombreOriginal, tipoContenido, tamanioBytes,
            checksumSha256, estado, fechaRegistroUtc, fechaAdjuncionUtc, fechaCambioEstadoUtc, idCorrelacionRegistro, idCorrelacionAdjuncion)
        VALUES (@fk, @userA, NEWID(), N'x.pdf', 'application/pdf', 1, @sha1, 'ATTACHED', SYSUTCDATETIME(), SYSUTCDATETIME(), SYSUTCDATETIME(), NEWID(), NEWID());
    END TRY
    BEGIN CATCH
        SET @err = ERROR_NUMBER();
    END CATCH
    SET @ok = IIF(@err = 547, 1, 0);
    EXEC #lb4d_expect 'INTEGRITY_FK_SOLICITUD', @ok;

    DECLARE @violations TABLE (id INT IDENTITY, caso VARCHAR(40), estado VARCHAR(10), solicitud UNIQUEIDENTIFIER, adjun DATETIME2(7),
        corrAdj UNIQUEIDENTIFIER, tipo VARCHAR(50), tam BIGINT, sha CHAR(64));
    INSERT @violations (caso, estado, solicitud, adjun, corrAdj, tipo, tam, sha) VALUES
        ('ATTACHED_WITHOUT_REQUEST', 'ATTACHED', NULL, SYSUTCDATETIME(), NEWID(), 'application/pdf', 1, @sha1),
        ('DRAFT_WITH_REQUEST', 'DRAFT', @req, NULL, NULL, 'application/pdf', 1, @sha1),
        ('ORPHAN_WITH_REQUEST', 'ORPHAN', @req, NULL, NULL, 'application/pdf', 1, @sha1),
        ('ATTACHED_WITHOUT_DATE', 'ATTACHED', @req, NULL, NEWID(), 'application/pdf', 1, @sha1),
        ('REPLACED_RESERVED', 'REPLACED', NULL, NULL, NULL, 'application/pdf', 1, @sha1),
        ('BAD_MIME', 'DRAFT', NULL, NULL, NULL, 'text/html', 1, @sha1),
        ('ZERO_SIZE', 'DRAFT', NULL, NULL, NULL, 'application/pdf', 0, @sha1),
        ('BAD_CHECKSUM', 'DRAFT', NULL, NULL, NULL, 'application/pdf', 1, UPPER(@sha1));
    SET @i = 1; SET @maxBad = (SELECT COUNT(*) FROM @violations);
    WHILE @i <= @maxBad
    BEGIN
        SET @err = 0;
        BEGIN TRY
            INSERT dbo.ArchivoSoporte (id, usuarioPropietario, solicitudRevisionAsistencia, nombreOriginal, tipoContenido, tamanioBytes,
                checksumSha256, estado, fechaRegistroUtc, fechaAdjuncionUtc, fechaCambioEstadoUtc, idCorrelacionRegistro, idCorrelacionAdjuncion)
            SELECT NEWID(), @userA, solicitud, N'x.pdf', tipo, tam, sha, estado, SYSUTCDATETIME(), adjun, SYSUTCDATETIME(), NEWID(), corrAdj
            FROM @violations WHERE id = @i;
        END TRY
        BEGIN CATCH
            SET @err = ERROR_NUMBER();
        END CATCH
        SET @ok = IIF(@err = 547, 1, 0);
        SET @etiqueta = CONCAT('INTEGRITY_CK_', (SELECT caso FROM @violations WHERE id = @i));
        EXEC #lb4d_expect @etiqueta, @ok;
        SET @i += 1;
    END

    -- un segundo soporte sobre la misma solicitud viola el indice unico filtrado
    SET @err = 0;
    BEGIN TRY
        INSERT dbo.ArchivoSoporte (id, usuarioPropietario, solicitudRevisionAsistencia, nombreOriginal, tipoContenido, tamanioBytes,
            checksumSha256, estado, fechaRegistroUtc, fechaAdjuncionUtc, fechaCambioEstadoUtc, idCorrelacionRegistro, idCorrelacionAdjuncion)
        VALUES (NEWID(), @userA, @req2, N'x.pdf', 'application/pdf', 1, @sha1, 'ATTACHED', SYSUTCDATETIME(), SYSUTCDATETIME(), SYSUTCDATETIME(), NEWID(), NEWID());
    END TRY
    BEGIN CATCH
        SET @err = ERROR_NUMBER();
    END CATCH
    SET @ok = IIF(@err IN (2601, 2627), 1, 0);
    EXEC #lb4d_expect 'INTEGRITY_ONE_SUPPORT_PER_REQUEST', @ok;

    -- ---------------------------------------------------------------- rollback atomico tras crear la solicitud
    -- Un trigger INSTEAD OF que anula el UPDATE de vinculo hace que @@ROWCOUNT <> 1 DESPUES de insertar la solicitud:
    -- el SP debe revertir la solicitud (savepoint) y dejar el archivo en DRAFT.
    DECLARE @file3 UNIQUEIDENTIFIER = NEWID();
    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    INSERT INTO #w EXEC dbo.usp_registrar_archivo_soporte @idArchivoSoporte = @file3, @nombreOriginal = N'tercero.png',
        @tipoContenido = 'image/png', @tamanioBytes = 55, @checksumSha256 = @sha1, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
    SET @ok = IIF(EXISTS (SELECT 1 FROM #w WHERE estadoResultado = 1), 1, 0);
    EXEC #lb4d_expect 'ROLLBACK_FIXTURE', @ok;
    EXEC (N'CREATE TRIGGER dbo.tr_lb4d_tmp_noop ON dbo.ArchivoSoporte INSTEAD OF UPDATE AS BEGIN SET NOCOUNT ON; END');
    TRUNCATE TABLE #w;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ARC_001',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    -- EXEC directo: ROLLBACK (savepoint) esta prohibido dentro de INSERT ... EXEC; el resultset (estadoResultado = 0, ARC_001)
    -- sale por el cliente y el estado se verifica por lectura.
    EXEC dbo.usp_radicar_solicitud_revision_asistencia_v2 @idEstudiante = @studentA, @idSesion = @session,
        @categoria = N'ASISTENCIA', @justificacion = N'Rollback QA', @idArchivoSoporte = @file3, @idCorrelacion = @corr,
        @idUsuarioEjecutor = @userA;
    SET @ok = IIF(NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE justificacionSolicitud = N'Rollback QA')
        AND EXISTS (SELECT 1 FROM dbo.ArchivoSoporte WHERE id = @file3 AND estado = 'DRAFT' AND solicitudRevisionAsistencia IS NULL), 1, 0);
    EXEC #lb4d_expect 'W2_ATOMIC_ROLLBACK', @ok;
    EXEC (N'DROP TRIGGER dbo.tr_lb4d_tmp_noop');

    -- ---------------------------------------------------------------- minimo privilegio con un usuario del rol runtime
    IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
        THROW 52202, 'TEST FAILED: LB004D rol_asistencias_runtime missing.', 1;
    CREATE USER [lb4d_runtime_tmp] WITHOUT LOGIN;
    ALTER ROLE [rol_asistencias_runtime] ADD MEMBER [lb4d_runtime_tmp];
    DECLARE @tablaDenegada INT = 0, @r1Permitido INT = 0, @w1Permitido INT = 0;
    BEGIN TRY
        EXECUTE AS USER = 'lb4d_runtime_tmp';
        BEGIN TRY
            DECLARE @cnt INT = (SELECT COUNT(*) FROM dbo.ArchivoSoporte);
        END TRY
        BEGIN CATCH
            SET @tablaDenegada = IIF(ERROR_NUMBER() = 229, 1, 0);
        END CATCH
        TRUNCATE TABLE #r1;
        INSERT INTO #r1 EXEC dbo.usp_consultar_archivo_soporte_autorizado @idArchivoSoporte = @file1, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
        SET @r1Permitido = IIF(EXISTS (SELECT 1 FROM #r1), 1, 0);
        TRUNCATE TABLE #w;
        INSERT INTO #w EXEC dbo.usp_registrar_archivo_soporte @idArchivoSoporte = @file1, @nombreOriginal = N'evidencia.pdf',
            @tipoContenido = 'application/pdf', @tamanioBytes = 1234, @checksumSha256 = @sha1, @idCorrelacion = @corr, @idUsuarioEjecutor = @userA;
        SET @w1Permitido = IIF(EXISTS (SELECT 1 FROM #w WHERE estadoResultado = 1), 1, 0);
        REVERT;
    END TRY
    BEGIN CATCH
        IF USER_NAME() = 'lb4d_runtime_tmp' REVERT;
        THROW;
    END CATCH
    SET @ok = IIF(@tablaDenegada = 1 AND @r1Permitido = 1 AND @w1Permitido = 1, 1, 0);
    EXEC #lb4d_expect 'RUNTIME_LEAST_PRIVILEGE', @ok;

    -- ---------------------------------------------------------------- la v1 sigue intacta (firma y comportamiento)
    SET @ok = IIF((SELECT COUNT(*) FROM sys.parameters WHERE object_id = OBJECT_ID('dbo.usp_radicar_solicitud_revision_asistencia')) = 8
        AND OBJECT_DEFINITION(OBJECT_ID('dbo.usp_radicar_solicitud_revision_asistencia')) LIKE '%@soporteNombre%'
        AND OBJECT_DEFINITION(OBJECT_ID('dbo.usp_radicar_solicitud_revision_asistencia')) NOT LIKE '%ArchivoSoporte%', 1, 0);
    EXEC #lb4d_expect 'V1_UNCHANGED', @ok;
END TRY
BEGIN CATCH
    IF USER_NAME() <> 'dbo' REVERT;
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
IF EXISTS (SELECT 1 FROM dbo.ArchivoSoporte WHERE nombreOriginal IN (N'evidencia.pdf', N'de-b.png', N'segundo.jpg', N'tercero.png'))
   OR EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE justificacionSolicitud IN (N'Sin soporte QA', N'Con soporte QA', N'Rollback QA'))
   OR EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'tr_lb4d_tmp_noop')
   OR EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'lb4d_runtime_tmp')
    THROW 52203, 'TEST FAILED: LB004D leaked fixture.', 1;
IF @@TRANCOUNT <> 0 THROW 52204, 'TEST FAILED: LB004D left transaction open.', 1;
-- Parametros invalidos => THROW. Fuera de la transaccion de fixtures: el SP corre con XACT_ABORT ON y el
-- THROW condena cualquier transaccion abierta (solo lectura, no hay datos que proteger).
DECLARE @errThrow INT = 0, @okThrow BIT;
BEGIN TRY
    EXEC dbo.usp_consultar_archivo_soporte_autorizado @idArchivoSoporte = @file1, @idCorrelacion = @corr, @idUsuarioEjecutor = NULL;
END TRY
BEGIN CATCH
    SET @errThrow = ERROR_NUMBER();
END CATCH
SET @okThrow = IIF(@errThrow = 51000, 1, 0);
EXEC #lb4d_expect 'R1_NULL_EXECUTOR_THROWS', @okThrow;
SET @errThrow = 0;
BEGIN TRY
    EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = NULL, @idCorrelacion = @corr;
END TRY
BEGIN CATCH
    SET @errThrow = ERROR_NUMBER();
END CATCH
SET @okThrow = IIF(@errThrow = 51000, 1, 0);
EXEC #lb4d_expect 'R2_NULL_EXECUTOR_THROWS', @okThrow;
DROP TABLE #w; DROP TABLE #r1; DROP TABLE #r2;
PRINT 'TEST_PASS:LB004D_SCHEMA_SHAPE';
PRINT 'TEST_PASS:LB004D_UTC_V2_DATETIME2_7';
PRINT 'TEST_PASS:LB004D_W1_VALID';
PRINT 'TEST_PASS:LB004D_W1_IDEMPOTENT';
PRINT 'TEST_PASS:LB004D_W1_INVALID';
PRINT 'TEST_PASS:LB004D_W2_WITHOUT_SUPPORT';
PRINT 'TEST_PASS:LB004D_W2_ATTACH';
PRINT 'TEST_PASS:LB004D_W2_IDEMPOTENT';
PRINT 'TEST_PASS:LB004D_W2_FOREIGN_AND_USED_FILE';
PRINT 'TEST_PASS:LB004D_W2_STUDENT_NOT_EXECUTOR';
PRINT 'TEST_PASS:LB004D_W2_INVALID_CONTEXT';
PRINT 'TEST_PASS:LB004D_R1_AUTHORIZATION_MATRIX';
PRINT 'TEST_PASS:LB004D_R2_TEACHER_SCOPE';
PRINT 'TEST_PASS:LB004D_INTEGRITY';
PRINT 'TEST_PASS:LB004D_W2_ATOMIC_ROLLBACK';
PRINT 'TEST_PASS:LB004D_RUNTIME_LEAST_PRIVILEGE';
PRINT 'TEST_PASS:LB004D_V1_UNCHANGED';
GO
DROP PROCEDURE #lb4d_expect;
GO
