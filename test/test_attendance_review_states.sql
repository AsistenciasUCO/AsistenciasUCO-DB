USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- TD-057: estados de solicitudes de revision. Contrato: P = Pendiente, A = Aprobada, R = Rechazada.
-- RADICAR -> P; APROBADA -> A; RECHAZADA -> R. Catalogo faltante -> fallo controlado sin escrituras.
-- Todo el escenario corre en una transaccion externa que se revierte al final.
PRINT 'TEST START: test_attendance_review_states';

DECLARE @group UNIQUEIDENTIFIER, @student UNIQUEIDENTIFIER, @enrollment UNIQUEIDENTIFIER, @teacher UNIQUEIDENTIFIER;
SELECT TOP 1 @group = eg.idGrupo, @student = eg.idEstudiante, @enrollment = eg.id, @teacher = g.idDocente
FROM dbo.uv_estudiante_grupo eg JOIN dbo.uv_grupo g ON g.id = eg.idGrupo
WHERE eg.codigoEstadoEstudiante = 'A' AND g.grupoEstaHablitado = 1
ORDER BY eg.id;
DECLARE @reason UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.RazonCausa WHERE codigo IN ('SJC', 'F'));
DECLARE @studentUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_estudiante_identidad WHERE id = @student);
DECLARE @teacherUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_docente_identidad WHERE id = @teacher);
IF @group IS NULL OR @student IS NULL OR @teacher IS NULL OR @studentUser IS NULL OR @teacherUser IS NULL OR @reason IS NULL
    THROW 52800, 'TEST FAILED: REVIEW_STATES fixture missing.', 1;

DECLARE @session UNIQUEIDENTIFIER = NEWID(), @attendance UNIQUEIDENTIFIER = NEWID(), @detail UNIQUEIDENTIFIER = NEWID();
DECLARE @sessionCode NVARCHAR(50) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8);
DECLARE @number INT = 1 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @group);
DECLARE @detailCode INT = 1 + (SELECT ISNULL(MAX(codigo), 0) FROM dbo.DetalleAsistencia);
DECLARE @corr UNIQUEIDENTIFIER, @msgUsuario NVARCHAR(4000), @msgTecnico NVARCHAR(4000);
DECLARE @request1 UNIQUEIDENTIFIER, @request2 UNIQUEIDENTIFIER, @codigo CHAR(1), @antes INT, @despues INT;

CREATE TABLE #rv (
    idCorrelacion UNIQUEIDENTIFIER NULL,
    mensajeUsuarioResultado NVARCHAR(MAX) NULL,
    mensajeTecnicoResultado NVARCHAR(MAX) NULL,
    estadoResultado INT NOT NULL
);

BEGIN TRANSACTION;
BEGIN TRY
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@session, N'QA Revision Estados', @number, @sessionCode, 1, @group,
        DATEADD(HOUR, 1, GETDATE()), DATEADD(HOUR, 2, GETDATE()));
    INSERT dbo.Asistencia (id, estudianteGrupo, sesion) VALUES (@attendance, @enrollment, @session);
    INSERT dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin)
    VALUES (@detail, @detailCode, @attendance, 0, @reason, DATEADD(HOUR, 1, GETDATE()), DATEADD(HOUR, 2, GETDATE()));

    -- 1. RADICAR -> estado P
    SET @corr = NEWID();
    TRUNCATE TABLE #rv;
    INSERT INTO #rv EXEC dbo.usp_radicar_solicitud_revision_asistencia
        @idEstudiante = @student, @idSesion = @session, @categoria = N'QA_ESTADOS',
        @justificacion = N'Solicitud de prueba de estados', @soporteNombre = N'soporte-qa.pdf',
        @soporteUrl = N'local://soporte-qa.pdf', @idCorrelacion = @corr, @idUsuarioEjecutor = @studentUser;
    IF NOT EXISTS (SELECT 1 FROM #rv WHERE estadoResultado = 1 AND idCorrelacion = @corr)
        THROW 52801, 'TEST FAILED: REVIEW_STATE_RADICAR_P radicar did not succeed.', 1;
    SELECT TOP 1 @request1 = id FROM dbo.SolicitudRevisionAsistencia WHERE asistencia = @attendance ORDER BY id;
    SELECT @codigo = e.codigo FROM dbo.SolicitudRevisionAsistencia s INNER JOIN dbo.Estado e ON e.id = s.estado WHERE s.id = @request1;
    IF @codigo <> 'P' THROW 52802, 'TEST FAILED: REVIEW_STATE_RADICAR_P expected estado P.', 1;
    PRINT 'TEST_PASS:REVIEW_STATE_RADICAR_P';

    -- 2. APROBADA -> estado A
    SET @corr = NEWID();
    TRUNCATE TABLE #rv;
    INSERT INTO #rv EXEC dbo.usp_resolver_solicitud_revision_asistencia
        @idSolicitud = @request1, @idDocente = @teacher, @accion = N'APROBADA',
        @respuestaDocente = N'Aprobada por QA', @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    IF NOT EXISTS (SELECT 1 FROM #rv WHERE estadoResultado = 1 AND idCorrelacion = @corr)
        THROW 52803, 'TEST FAILED: REVIEW_STATE_APROBAR_A resolve APROBADA did not succeed.', 1;
    SELECT @codigo = e.codigo FROM dbo.SolicitudRevisionAsistencia s INNER JOIN dbo.Estado e ON e.id = s.estado WHERE s.id = @request1;
    IF @codigo <> 'A' THROW 52804, 'TEST FAILED: REVIEW_STATE_APROBAR_A expected estado A.', 1;
    PRINT 'TEST_PASS:REVIEW_STATE_APROBAR_A';

    -- 3. RECHAZADA -> estado R (segunda solicitud sobre la misma asistencia)
    SET @corr = NEWID();
    TRUNCATE TABLE #rv;
    INSERT INTO #rv EXEC dbo.usp_radicar_solicitud_revision_asistencia
        @idEstudiante = @student, @idSesion = @session, @categoria = N'QA_ESTADOS',
        @justificacion = N'Segunda solicitud de prueba', @soporteNombre = N'soporte-qa-2.pdf',
        @soporteUrl = N'local://soporte-qa-2.pdf', @idCorrelacion = @corr, @idUsuarioEjecutor = @studentUser;
    SELECT TOP 1 @request2 = id FROM dbo.SolicitudRevisionAsistencia WHERE asistencia = @attendance AND id <> @request1 ORDER BY id;
    SET @corr = NEWID();
    TRUNCATE TABLE #rv;
    INSERT INTO #rv EXEC dbo.usp_resolver_solicitud_revision_asistencia
        @idSolicitud = @request2, @idDocente = @teacher, @accion = N'RECHAZADA',
        @respuestaDocente = N'Rechazada por QA', @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    IF NOT EXISTS (SELECT 1 FROM #rv WHERE estadoResultado = 1 AND idCorrelacion = @corr)
        THROW 52805, 'TEST FAILED: REVIEW_STATE_RECHAZAR_R resolve RECHAZADA did not succeed.', 1;
    SELECT @codigo = e.codigo FROM dbo.SolicitudRevisionAsistencia s INNER JOIN dbo.Estado e ON e.id = s.estado WHERE s.id = @request2;
    IF @codigo <> 'R' THROW 52806, 'TEST FAILED: REVIEW_STATE_RECHAZAR_R expected estado R.', 1;
    PRINT 'TEST_PASS:REVIEW_STATE_RECHAZAR_R';

    -- 4. P faltante -> radicar falla controlado (CAT_001), cero inserciones.
    UPDATE dbo.Estado SET codigo = 'Z' WHERE codigo = 'P';
    SELECT @antes = COUNT(*) FROM dbo.SolicitudRevisionAsistencia WHERE asistencia = @attendance;
    SET @corr = NEWID();
    TRUNCATE TABLE #rv;
    INSERT INTO #rv EXEC dbo.usp_radicar_solicitud_revision_asistencia
        @idEstudiante = @student, @idSesion = @session, @categoria = N'QA_ESTADOS',
        @justificacion = N'Sin estado P', @soporteNombre = N'soporte-qa-3.pdf',
        @soporteUrl = N'local://soporte-qa-3.pdf', @idCorrelacion = @corr, @idUsuarioEjecutor = @studentUser;
    UPDATE dbo.Estado SET codigo = 'P' WHERE codigo = 'Z';
    SELECT @despues = COUNT(*) FROM dbo.SolicitudRevisionAsistencia WHERE asistencia = @attendance;
    IF NOT EXISTS (SELECT 1 FROM #rv WHERE estadoResultado = 0 AND idCorrelacion = @corr)
        THROW 52807, 'TEST FAILED: REVIEW_MISSING_P_CONTROLLED expected estado 0.', 1;
    IF @antes <> @despues THROW 52808, 'TEST FAILED: REVIEW_MISSING_P_CONTROLLED inserted a request without P.', 1;
    PRINT 'TEST_PASS:REVIEW_MISSING_P_CONTROLLED';

    -- 5. A faltante -> resolver APROBADA falla controlado, la solicitud conserva su estado.
    UPDATE dbo.Estado SET codigo = 'Z' WHERE codigo = 'A';
    SET @corr = NEWID();
    TRUNCATE TABLE #rv;
    INSERT INTO #rv EXEC dbo.usp_radicar_solicitud_revision_asistencia
        @idEstudiante = @student, @idSesion = @session, @categoria = N'QA_ESTADOS',
        @justificacion = N'Solicitud para probar A faltante', @soporteNombre = N'soporte-qa-4.pdf',
        @soporteUrl = N'local://soporte-qa-4.pdf', @idCorrelacion = @corr, @idUsuarioEjecutor = @studentUser;
    SELECT TOP 1 @request1 = id FROM dbo.SolicitudRevisionAsistencia
    WHERE asistencia = @attendance AND justificacionSolicitud = N'Solicitud para probar A faltante';
    SET @corr = NEWID();
    TRUNCATE TABLE #rv;
    INSERT INTO #rv EXEC dbo.usp_resolver_solicitud_revision_asistencia
        @idSolicitud = @request1, @idDocente = @teacher, @accion = N'APROBADA',
        @respuestaDocente = N'Sin estado A', @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    UPDATE dbo.Estado SET codigo = 'A' WHERE codigo = 'Z';
    SELECT @codigo = e.codigo FROM dbo.SolicitudRevisionAsistencia s INNER JOIN dbo.Estado e ON e.id = s.estado WHERE s.id = @request1;
    IF NOT EXISTS (SELECT 1 FROM #rv WHERE estadoResultado = 0 AND idCorrelacion = @corr)
        THROW 52809, 'TEST FAILED: REVIEW_MISSING_A_CONTROLLED expected estado 0.', 1;
    IF @codigo <> 'P' THROW 52810, 'TEST FAILED: REVIEW_MISSING_A_CONTROLLED changed the request state.', 1;
    PRINT 'TEST_PASS:REVIEW_MISSING_A_CONTROLLED';

    -- 6. R faltante -> resolver RECHAZADA falla controlado, la solicitud conserva su estado.
    UPDATE dbo.Estado SET codigo = 'Z' WHERE codigo = 'R';
    SET @corr = NEWID();
    TRUNCATE TABLE #rv;
    INSERT INTO #rv EXEC dbo.usp_resolver_solicitud_revision_asistencia
        @idSolicitud = @request1, @idDocente = @teacher, @accion = N'RECHAZADA',
        @respuestaDocente = N'Sin estado R', @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    UPDATE dbo.Estado SET codigo = 'R' WHERE codigo = 'Z';
    SELECT @codigo = e.codigo FROM dbo.SolicitudRevisionAsistencia s INNER JOIN dbo.Estado e ON e.id = s.estado WHERE s.id = @request1;
    IF NOT EXISTS (SELECT 1 FROM #rv WHERE estadoResultado = 0 AND idCorrelacion = @corr)
        THROW 52811, 'TEST FAILED: REVIEW_MISSING_R_CONTROLLED expected estado 0.', 1;
    IF @codigo <> 'P' THROW 52812, 'TEST FAILED: REVIEW_MISSING_R_CONTROLLED changed the request state.', 1;
    PRINT 'TEST_PASS:REVIEW_MISSING_R_CONTROLLED';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;

IF (SELECT COUNT(*) FROM dbo.Estado WHERE codigo IN ('P', 'A', 'R')) <> 3
    THROW 52813, 'TEST FAILED: REVIEW_STATES catalog P/A/R incomplete after rollback.', 1;
IF EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = @session) OR EXISTS (SELECT 1 FROM dbo.Asistencia WHERE id = @attendance)
    THROW 52814, 'TEST FAILED: REVIEW_STATES leaked fixture.', 1;
IF @@TRANCOUNT <> 0 THROW 52815, 'TEST FAILED: REVIEW_STATES left transaction open.', 1;
PRINT 'TEST END: test_attendance_review_states';
GO
